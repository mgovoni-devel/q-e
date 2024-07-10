!
! Copyright (C) 2001-2015 Quantum ESPRESSO group
! This file is distributed under the terms of the
! GNU General Public License. See the file `License'
! in the root directory of the present distribution,
! or http://www.gnu.org/copyleft/gpl.txt .
!
!
!----------------------------------------------------------------------------
SUBROUTINE compute_becsum( iflag )
  !----------------------------------------------------------------------------
  !! Compute "becsum" = \sum_i w_i <psi_i|beta_l><beta_m|\psi_i> term.
  !! Output in module uspp and (PAW only) in rho%bec (symmetrized)
  !! if iflag = 1, weights w_k are re-computed.
  !
  USE kinds,                ONLY : DP
  USE control_flags,        ONLY : gamma_only
  USE klist,                ONLY : nks, xk, ngk, igk_k
  USE lsda_mod,             ONLY : lsda, nspin, current_spin, isk
  USE io_files,             ONLY : iunwfc, nwordwfc
  USE buffers,              ONLY : get_buffer
  USE scf,                  ONLY : rho
  USE uspp,                 ONLY : nkb, vkb, becsum, okvan
  USE uspp_param,           ONLY : nhm
  USE wavefunctions,        ONLY : evc
  USE wvfct,                ONLY : nbnd, npwx, wg
  USE mp_pools,             ONLY : inter_pool_comm
  USE mp_bands,             ONLY : intra_bgrp_comm, inter_bgrp_comm 
  USE mp,                   ONLY : mp_sum, mp_get_comm_null
  USE paw_symmetry,         ONLY : PAW_symmetrize
  USE paw_variables,        ONLY : okpaw
  USE becmod,               ONLY : allocate_bec_type_acc, &
                                   deallocate_bec_type_acc, becp
  USE uspp_init,            ONLY : init_us_2
  !
  IMPLICIT NONE
  !
  INTEGER, INTENT(IN) :: iflag
  !
  INTEGER :: ik, & ! counter on k points
             ibnd_start, ibnd_end, this_bgrp_nbnd ! first, last and number of band in this bgrp
  !
  !
  IF ( .NOT. okvan ) RETURN
  !
  CALL start_clock( 'compute_becsum' )
  !
  ! ... calculates weights of Kohn-Sham orbitals
  !
  IF ( iflag == 1) CALL weights( )
  !
  !$acc kernels
  becsum(:,:,:) = 0.D0
  !$acc end kernels
  CALL allocate_bec_type_acc( nkb,nbnd, becp,intra_bgrp_comm )
  CALL divide( inter_bgrp_comm, nbnd, ibnd_start, ibnd_end )
  this_bgrp_nbnd = ibnd_end - ibnd_start + 1
  !
  k_loop: DO ik = 1, nks
     !
     IF ( lsda ) current_spin = isk(ik)
     IF ( nks > 1 ) CALL get_buffer( evc, nwordwfc, iunwfc, ik )
     !$acc update device(evc)
     !
     IF ( nkb > 0 ) CALL init_us_2( ngk(ik), igk_k(1,ik), xk(1,ik), vkb, .TRUE. )
     !
     ! ... actual calculation is performed (on GPU) inside routine "sum_bec"
     !
     CALL sum_bec( ik, current_spin, ibnd_start, ibnd_end, this_bgrp_nbnd )
     !
  ENDDO k_loop
  !
  ! ... Use host copy to do the communications
  !$acc update host(becsum)
  !
  ! ... If the <beta|psi> are distributed, sum over bands
  !
  IF( becp%comm /= mp_get_comm_null() .AND. nhm > 0) &
       CALL mp_sum( becsum, becp%comm )
  CALL deallocate_bec_type_acc( becp )
  !
  ! ... becsums must be also be summed over bands (with bgrp parallelization)
  ! ... and over k-points (unsymmetrized).
  !
  CALL mp_sum(becsum, inter_bgrp_comm )
  CALL mp_sum(becsum, inter_pool_comm )
  !
  ! ... Needed for PAW: becsums are stored into rho%bec and symmetrized so that they reflect
  ! ... a real integral in k-space, not only on the irreducible zone. 
  ! ... No need to symmetrize becsums or to align GPU and CPU copies: they are used only here.
  !
  IF ( okpaw )  THEN
     rho%bec(:,:,:) = becsum(:,:,:)
     CALL PAW_symmetrize( rho%bec )
  ENDIF
  !
  CALL stop_clock( 'compute_becsum' )
  !
END SUBROUTINE compute_becsum
