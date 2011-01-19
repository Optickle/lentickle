% pickle.result = pickleEngine(pickle, pos, f, sigAC, mMech)
%   generate pickle result matrices, TFs, etc.
%   sigAC and mMech will be generated if not given as arguments
%

function [rslt,fDC,sigDC,sigAC, mMech] = lentickleEngine(lentickle, pos, f, sigAC, mMech)
  
  pp = lentickle.param;

  
  % sizes of things
  Nfreq = numel(f);
  Nsens = pp.Nsens;
  Ndof = pp.Ndof;
  Nmirr = pp.Nmirr;
  Ndrive = lentickle.opt.Ndrive;
  
  % call tickle to compute fields and TFs
  if( nargin < 5 )
      [fDC,sigDC,sigAC,mMech] = tickle(lentickle.opt, pos, f, pp.vMirr);
      mirrReduce = zeros(Nmirr,Ndrive);
      for jj = 1:length(pp.vMirr)
          mirrReduce(jj,pp.vMirr(jj)) = 1;
      end
      
      % now we take out the empty parts of the matricies
      sigAC = mult3D2D(sigAC,mirrReduce);
      
      mMech = mult2D3D(mirrReduce.',mult3D2D(mMech,mirrReduce));
  end
  
  % get loop TFs
  hCtrl = pickleMakeFilt(f, pp.ctrlFilt);
  hMirr = pickleMakeFilt(f, pp.mirrFilt);
  hPend = pickleMakeFilt(f, pp.pendFilt);
  
  %%%%%%%%%%%%%%%%% initialize result matrices
  rslt.Nfreq = Nfreq;
  rslt.Nsens = Nsens;
  rslt.Ndof = Ndof;
  rslt.Nmirr = Nmirr;
  
  rslt.sensCL = zeros(Nsens, Nsens, Nfreq);
  rslt.errCL = zeros(Ndof, Ndof, Nfreq);
  rslt.ctrlCL = zeros(Ndof, Ndof, Nfreq);
  rslt.corrCL = zeros(Nmirr, Nmirr, Nfreq);
  rslt.mirrCL = zeros(Nmirr, Nmirr, Nfreq);
  
  rslt.errOL = zeros(Ndof, Ndof, Nfreq);
  
  rslt.sensErr = zeros(Ndof, Nsens, Nfreq);
  rslt.errCtrl = zeros(Ndof, Ndof, Nfreq);
  rslt.ctrlCorr = zeros(Nmirr, Ndof, Nfreq);
  rslt.corrMirr = zeros(Nmirr, Nmirr, Nfreq);
  rslt.mirrSens = zeros(Nsens, Nmirr, Nfreq);
  rslt.corrSens = zeros(Nsens, Nmirr, Nfreq);
  
  rslt.mMirr = zeros(Nmirr, Nmirr, Nfreq);
  rslt.mirrSpot = zeros(Nmirr, Nmirr, Nfreq);
  
  % compute result matrices for each frequency
  probeSens = pp.probeSens;
  sensDof = pp.sensDof;
  dofMirr = pp.dofMirr;
  mirrDrive = pp.mirrDrive;
  driveMirr = pp.driveMirr;
  
  
  
  % if desired, set UGF directly to desired value for each DOF
  if(any(strcmp(fieldnames(pp),'setUgfDof')))
    setUgfDof = pp.setUgfDof;
    ugfDof = setUgfDof;

    for m = 1:Ndof
      if isnan(setUgfDof(m)) %skip NaNs because they mean don't change it
          continue
      end
      % find the nearest f index and use that
      [fDelta,fIndex] = min(abs(f-setUgfDof(m)));
      ugfDof(m) = f(fIndex);
      
      % calculate the current gain at that frequency
      dofGain = sensDof * probeSens * sigAC(:, :, fIndex) * mirrDrive *...
            diag(hPend(fIndex, :)) * diag(hMirr(fIndex, :)) * dofMirr *...
            diag(hCtrl(fIndex, :));
      
      dofGain = dofGain(m,m);
      
      dofSign = sign(angle(dofGain));
      
      % divide out the gain to make it 1 at the desired frequency
      sensDof(m,:) = pp.sensDof(m,:) / abs(dofGain) * dofSign;
    end
    
    % store the true UGFs
    rslt.ugfDof = ugfDof;
  end
  
  eyeSens = eye(Nsens);
  eyeDof = eye(Ndof);
  eyeMirr = eye(Nmirr);

  % prevent scale warnings
  sWarn = warning('off', 'MATLAB:nearlySingularMatrix');

  for n = 1:Nfreq
    % use maps to produce mirrSens
    mirrSens = probeSens * sigAC(:, :, n) * mirrDrive;
    
    % make piecewise TFs
    errCtrl = diag(hCtrl(n, :));
    ctrlCorr = diag(hMirr(n, :)) * dofMirr;
    corrMirr = diag(hPend(n, :));

    % make half-loop pairs
    corrSens = mirrSens * corrMirr;
    sensCorr = ctrlCorr * errCtrl * sensDof;
    
    % make open-loop TFs
    sensOL = corrSens * sensCorr;
    errOL = sensDof * corrSens * ctrlCorr * errCtrl;
    ctrlOL = errCtrl * sensDof * corrSens * ctrlCorr;
    corrOL = sensCorr * corrSens;
    mirrOL = corrMirr * sensCorr * mirrSens;
    
    % store results
    rslt.sensErr(:, :, n) = sensDof;
    rslt.errCtrl(:, :, n) = errCtrl;
    rslt.ctrlCorr(:, :, n) = ctrlCorr;
    rslt.corrMirr(:, :, n) = corrMirr;
    rslt.mirrSens(:, :, n) = mirrSens;
    rslt.corrSens(:, :, n) = corrSens;
    
    rslt.errOL(:, :, n) = errOL;

    rslt.sensCL(:, :, n) = inv(eyeSens - sensOL);
    rslt.errCL(:, :, n) = inv(eyeDof - errOL);
    rslt.ctrlCL(:, :, n) = inv(eyeDof - ctrlOL);
    rslt.corrCL(:, :, n) = inv(eyeMirr - corrOL);
    rslt.mirrCL(:, :, n) = inv(eyeMirr - mirrOL);
    
    rslt.mMirr(:, :, n) = driveMirr * mMech(:, :, n) * mirrDrive;
    
%    rslt.mirrSpot(:, :, n) = probeSpot * sigAC(:, :, n) * mirrDrive;
  end

  % reset scale warning state
  warning(sWarn.state, sWarn.identifier);
  
  % copy some parameter matrices
  rslt.mirrDof = pp.mirrDof;
  
  % test point names
  rslt.testPoints = {'sens', 'err', 'ctrl', 'corr', 'mirr'};
  rslt.Ntp = numel(rslt.testPoints);
  
  % copy names
  rslt.mirrNames = pp.mirrNames;
  rslt.sensNames = pp.sensNames;
  rslt.dofNames = pp.dofNames;
  
  
  % make capitalized version of names
  rslt.testPointsUpper = rslt.testPoints;
  for n = 1:rslt.Ntp
    nameTmp = rslt.testPoints{n};
    nameTmp(1) = upper(nameTmp(1));
    rslt.testPointsUpper{n} = nameTmp;
  end
  
end

function Z = mult3D2D(X,Y)

    [A,B,C] = size(X);
    [B2,D]  = size(Y);
    
    if B ~= B2
        error('The second length of the 3D matrix must match the first of the 2D')
    end
    
    
    %# calculate result in one big matrix
    Z = reshape(reshape(permute(X, [2 1 3]), [A B*C]), [B A*C]).' * Y;

    %'# split into third dimension
    Z = permute(reshape(Z.',[D A C]),[2 1 3]);
end


function Z = mult2D3D(Y,X)
    %Z = permute( mult3D2D(permute(X,[2 1 3]),Y.') , [2,1,3]);

    [A,B,C] = size(X);
    [B2,D]  = size(Y);
    
    if A ~= D
        error('The first length of the 3D matrix must match the second of the 2D')
    end
    
    
    %# calculate result in one big matrix
    Z = Y * reshape(reshape(permute(X, [2 1 3]), [A*C B]), [B*C A]).';

    %'# split into third dimension
    Z = permute(reshape(Z.',[B B2 C]),[2 1 3]);
end