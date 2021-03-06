%IBVS   Implement classical IBVS for point features
%
% A concrete class for simulation of image-based visual servoing (IBVS), a subclass of
% VisualServo.  Two windows are shown and animated:
%   - The camera view, showing the desired view (*) and the 
%     current view (o)
%   - The external view, showing the target points and the camera
%
% Methods::
% run            Run the simulation, complete results kept in the object
% plot_p         Plot image plane coordinates of points vs time
% plot_vel       Plot camera velocity vs time
% plot_camera    Plot camera pose vs time
% plot_jcond     Plot Jacobian condition vs time 
% plot_z         Plot point depth vs time
% plot_error     Plot feature error vs time
% plot_all       Plot all of the above in separate figures
% char           Convert object to a concise string
% display        Display the object as a string
%
% Example::
%         cam = CentralCamera('default');    
%         ibvs = IBVS_l(cam, 'example'); 
%         ibvs.run()
%
% References::
% - Robotics, Vision & Control, Chap 15
%   P. Corke, Springer 2011.
%
% Notes::
% - The history property is a vector of structures each of which is a snapshot at
%   each simulation step of information about the image plane, camera pose, error, 
%   Jacobian condition number, error norm, image plane size and desired feature 
%   locations.
% - Lines are constructed by joining consecutive point features.
%
% See also VisualServo, PBVS, IBVS_l, IBVS_e.
% IMPLEMENTATION NOTE
%
% 1.  As per task function notation (Chaumette papers) the error is
%     defined as actual-demand, the reverse of normal control system
%     notation.
% 2.  The gain, lambda, is always positive
% 3.  The negative sign is written into the control law

classdef IBVS_l < VisualServo

    properties
        lambda          % IBVS gain
        eterm

        f_star_retinal         % desired theta-rho coordinates
        f_star
        planes
    end

    methods

        function ibvs = IBVS_l(cam, varargin)
            %IBVS_l.IBVS_l Create IBVS line visual servo object
            %
            % IB = IBVS_l(camera, options)
            %
            % Options::
            % 'example'         Use set of canned parameters
            % 'niter',N         Maximum number of iterations
            % 'eterm',E         Terminate when norm of feature error < E
            % 'lambda',L        Control gain, positive definite scalar or matrix
            % 'T0',T            The initial pose
            % 'Tf',T            The final camera pose used only to determine desired
            %                   image plane coordinates (default 1m in z-direction)
            % 'P',p             The set of world points (3xN)
            % 'planes',P        The world planes holding the lines (4xN)
            % 'fps',F           Number of simulation frames per second (default t)
            % 'verbose'         Print out extra information during simulation
            %
            % Notes::
            % - If 'P' is specified the lines join points 1-2, 2-3, N-1.
            %
            % See also VisualServo.

            % invoke superclass constructor
            ibvs = ibvs@VisualServo(cam, varargin{:});

            % handle arguments
            opt.eterm = 0.01;
            opt.planes = [];
            opt.lambda = 0.08;         % control gain
            opt.example = false;
            
            opt = tb_optparse(opt, ibvs.arglist);

            if opt.example
                % run a canned example
                fprintf('----------------------------\n');
                fprintf('canned example, line-based IBVS with three lines\n');
                fprintf('----------------------------\n');
                ibvs.planes = repmat([0 0 1 -3]', 1, 3);
                ibvs.P = circle([0 0 3], 1, 'n', 3);
                ibvs.T0 = transl(1,1,-3)*trotz(0.6);
            else
                ibvs.planes = opt.planes;
            end

            % copy options to IBVS object
            ibvs.lambda = opt.lambda;
            ibvs.eterm = opt.eterm;
            
            
            % init the graphics
            clf
            subplot(121);
            ibvs.camera.plot_create(gca)
            
            subplot(122)
            % this is the 'external' view of the points and the camera
            PP = [ibvs.P ibvs.P(:,1)];
            plot3(PP(1,:), PP(2,:), PP(3,:), 'r', 'LineWidth', 5)
            ibvs.camera.plot_camera();
            plotvol([-1 1 -1 1 -3 3])
            view(16, 28);
            grid on
            set(gcf, 'Color', 'w')
            
            ibvs.type = 'line';
            
        end

        function init(vs)
            %IBVS_l.init Initialize simulation
            %
            % IB.init() initializes the simulation.  Implicitly called by
            % IB.run().
            %
            % See also VisualServo, IBVS_l.run.

            if isempty(vs.Tf)
                vs.Tf = transl(0, 0, 1);
                warning('setting Tf to default');
            end
            


            % final pose is specified in terms of a camera-target pose
            vs.f_star_retinal = vs.getlines(vs.Tf, inv(vs.camera.K)); % in retinal coordinates
            vs.f_star = vs.getlines(vs.Tf); % in image coordinates

            % initialize the vservo variables
            vs.camera.T = vs.T0;    % set camera back to its initial pose
            vs.Tcam = vs.T0;                % initial camera/robot pose
            
            vs.history = [];
            

        end

        function lines = getlines(vs, T, scale)
            % one line per column
            %  row 1 theta
            %  row 2 rho
            % project corner points to image plane
            p = vs.camera.project(vs.P, 'pose', T);
            if nargin > 2
                p = homtrans(scale, p);
            end
            % compute lines and their slope and intercept
            for i=1:numcols(p)
                j = mod(i,numcols(p))+1;
                theta = atan2(p(2,j)-p(2,i), p(1,i)-p(1,j));
                rho = sin(theta)*p(1,i) + cos(theta)*p(2,i);
                lines(1,i) = theta; lines(2,i) = rho;
            end
        end

        function status = step(vs)
            %IBVS_l.step Simulate one time step
            %
            % STAT = IB.step() performs one simulation time step of IBVS.  It is
            % called implicitly from the superclass run method.  STAT is
            % one if the termination condition is met, else zero.
            %
            % See also VisualServo, IBVS_l.run.
            status = 0;
            Zest = [];
            
            % compute the lines
            f = vs.getlines(vs.Tcam);

            % now plot them
            vs.camera.clf();
            vs.camera.hold(true);
            colors = 'rgb';
            for i=1:3
                % plot current line
                vs.camera.plot_line_tr(f(:,i), colors(i), 'LineWidth', 2);
                % plot demanded line
                vs.camera.plot_line_tr(vs.f_star(:,i), [colors(i) '--'], 'LineWidth', 2);
            end

            f_retinal = vs.getlines(vs.Tcam, inv(vs.camera.K));

            % compute image plane error as a column
            e = f_retinal - vs.f_star_retinal;   % feature error on retinal plane
            e = e(:);
            for i=1:2:numrows(e)
                e(i) = angdiff(e(i));
            end
        
            J = vs.camera.visjac_l(f_retinal, vs.planes);

            % compute the velocity of camera in camera frame
            v = -vs.lambda * pinv(J) * e;
            if vs.verbose
                fprintf('v: %.3f %.3f %.3f %.3f %.3f %.3f\n', v);
            end

            % update the camera pose
            Td = delta2tr(v);    % differential motion

            vs.Tcam = vs.Tcam * Td;       % apply it to current pose
            vs.Tcam = trnorm(vs.Tcam);

            % update the exteranl view camera pose
            vs.camera.T = vs.Tcam;

            % update the history variables
            hist.f = f(:);
            vel = tr2delta(Td);
            hist.vel = vel;
            hist.e = e;
            hist.en = norm(e);
            hist.jcond = cond(J);
            hist.Tcam = vs.Tcam;

            vs.history = [vs.history hist];
            if norm(e) < vs.eterm
                status = 1;
                return
            end
        end
    end % methods
end % class
