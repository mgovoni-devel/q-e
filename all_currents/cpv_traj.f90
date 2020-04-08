module cpv_traj
    use kinds, only : dp
    use traj_object ! timestep,trajectory and all subroutines that starts with trajectory_

    implicit none

    type cpv_trajectory
        type(trajectory) :: traj
        character(len=256) :: fname = ''
        integer :: iounit_pos=-1, iounit_vel=-1
        logical :: is_open=.false.
        real(dp) :: tau_fac=1.0_dp, vel_fac=1.0_dp, tps_fac=1.0_dp
    end type

    contains

    function newunit() result(unit)
      integer  :: unit
      integer, parameter :: LUN_MIN=10, LUN_MAX=2000
      logical :: opened
      integer :: lun
      do lun=LUN_MIN,LUN_MAX
        inquire(unit=lun,opened=opened)
        if (.not. opened) then
          unit=lun
          exit
        end if
      end do
    end function newunit
 
    subroutine cpv_trajectory_initialize(t, fname, natoms, tau_fac, vel_fac,tps_fac)
        type(cpv_trajectory), intent(inout) :: t
        character(len=256), intent(in) :: fname
        integer, intent(in) :: natoms
        real(dp), intent(in) :: tau_fac,vel_fac,tps_fac
        integer :: iostat
        ! try to open fname, allocate traj
        t%iounit_pos=newunit()
        open(unit=t%iounit_pos, file=trim(fname) // '.pos', iostat=iostat )
        if (iostat /= 0) &
            call errore('cpv_trajectory_initialize', 'error opening file "' // trim(fname) // '.pos"',1)
        t%iounit_vel=newunit()
        open(unit=t%iounit_vel,file=trim(fname) // '.vel' )
        if (iostat /= 0) &
            call errore('cpv_trajectory_initialize', 'error opening file "' // trim(fname) // '.vel"',1)
        t%is_open=.true.
        t%tau_fac=tau_fac
        t%vel_fac=vel_fac
        t%tps_fac=tps_fac
        t%fname=fname
        !allocate traj
        call trajectory_allocate(t%traj,natoms,50) !start allocating space for 50 steps
       
    end subroutine

    subroutine cpv_trajectory_close(t)
    type(cpv_trajectory), intent(inout) :: t
        close(t%iounit_pos)
        close(t%iounit_vel)
        t%is_open=.false. 
    end subroutine

    function cpv_trajectory_read_step(t) result (res)
        type(cpv_trajectory), intent(inout) :: t
        logical :: res
        type(timestep) :: tstep !this internally is only a pointer to a bigger allocated array
        real(dp) :: tps_
        integer :: nstep_,iatom,i
        if (.not. t%is_open) then
            res = .false.
            return
        endif        

        !try to read a new step, if success return true
        !get some space (that can be used again
        call trajectory_get_temporary(t%traj,t%traj%natoms,tstep) ! first get a temporary, then eventually confirm it as valid
        
        !read header
        read (t%iounit_pos,*, err=100, end=100) tstep%nstep, tstep%tps
        read (t%iounit_vel,*, err=100, end=100) nstep_, tps_
        if (tstep%nstep /= nstep_ .or. tstep%tps /= tps_ ) then
            write (*,*) 'error in reading: inconsistent timestep headers in .pos and .vel files!', &
                        nstep_,tps_,tstep%nstep, tstep%tps 
            goto 100
        end if

        ! read trajectory
        do iatom = 1, t%traj%natoms
            read (t%iounit_pos,*, err=100, end=100) (tstep%tau(i,iatom),i=1,3)
            read (t%iounit_vel,*, err=100, end=100) (tstep%vel(i,iatom),i=1,3)
        enddo

        !apply factors
        tstep%tau = tstep%tau * t%tau_fac
        tstep%vel = tstep%vel * t%vel_fac
        tstep%tps = tstep%tps * t%tps_fac

        !store temporary in trajectory
        call trajectory_push_back_last_temporary(t%traj)

        res = .true.
        
        return

        !reading error
        100 res=.false.
        call cpv_trajectory_close(t)

    end function

    subroutine cpv_trajectory_get_step(t, idx, tstep)
        type(cpv_trajectory), intent(in) :: t
        type(timestep), intent(out) :: tstep
        integer, intent(in) :: idx

        ! get the timestep data
        call trajectory_get(t%traj,idx,tstep)

    end subroutine

    subroutine cpv_trajectory_deallocate(t)
        type(cpv_trajectory), intent(inout) :: t

        !deallocate stuff
        call trajectory_deallocate(t%traj)
        call cpv_trajectory_close(t)

    end subroutine

end module
