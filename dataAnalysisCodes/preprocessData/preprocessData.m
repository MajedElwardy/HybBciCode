function preprocessData

%% =====================================================================================
%                           INITIALIZE PARAMETERS

addpath(fullfile(cd, 'xmlRelatedFncts'));
expDir      = 'd:\KULeuven\PhD\Work\Hybrid-BCI\';
dataDir     = fullfile(expDir, 'HybBciData');
outputDir	= fullfile(expDir, 'HybBciProcessedData');
sessionName = '2012-11-12-Adrien';

% file lists
%--------------------------------------------------------------------------
folderName  = fullfile(dataDir, sessionName);
fileList    = cellstr(ls(sprintf('%s\\*.bdf', folderName)));
parFileList = cellstr(ls(sprintf('%s\\*.mat', folderName)));
xmlFileList = cellstr(ls(sprintf('%s\\*unfolded-scenario.xml', folderName)));

% identify eog calibration file
%--------------------------------------------------------------------------
temp                = strfind(fileList, 'eog-calibration');
iEogFile            = sum( find ( cellfun(@(x) ~isempty(x), temp ) ) );
if iEogFile
    eogCalibrationFile  = fileList{iEogFile};
    fileList(iEogFile)  = [];
end

% identify main parameter file
%--------------------------------------------------------------------------
temp                = strfind(parFileList, 'ExperimentDetail');
iMainPar            = sum( find ( cellfun(@(x) ~isempty(x), temp ) ) );
if iMainPar
    mainParamFile           = parFileList{iMainPar};
    parFileList(iMainPar)   = [];
else
    error('main parameter file not found!!');
end
mainExpPars = load( fullfile(folderName, mainParamFile) );

% Check that only one bdf file is present
%--------------------------------------------------------------------------
if numel(fileList) ~= 1
    error('not only one bdf file!!');
end
dataFile = fileList{1};

% create output folders
%--------------------------------------------------------------------------
outputFolder        = fullfile(outputDir, sessionName);
rawOutputFolder     = fullfile(outputFolder, 'nonEogCorreted');
if ~exist( rawOutputFolder, 'dir' )
    mkdir(rawOutputFolder)
end

if iEogFile
    eogCorrOutputFolder = fullfile(outputFolder, 'eogCorrected');
    if ~exist( eogCorrOutputFolder, 'dir' )
        mkdir(eogCorrOutputFolder)
    end
end

% external channels
%--------------------------------------------------------------------------
refChanNames    = {'EXG1', 'EXG2'};
discardChanNames= {'EXG7', 'EXG8'};
eogChan.Names   = {'EXG3', 'EXG4', 'EXG5', 'EXG6'};
eogChan.Labels  = {'left', 'right', 'up', 'down'};
eogChan.HEch    = 'left - right';
eogChan.VEch    = 'up - down';
eogChan.REch    = '(up + down)/2';


% check the lists of files
%--------------------------------------------------------------------------

% check that the lists of .xml and .mat file are consistent 
tag = '-unfolded-scenario';
xmlLabels = cellfun(@(x) x( 1 : strfind(x, tag)-1 ), xmlFileList, 'UniformOutput', false);
tag = '.mat';
parLabels = cellfun(@(x) x( 1 : strfind(x, tag)-1 ), parFileList, 'UniformOutput', false);
if ~isequal(xmlLabels, parLabels)
    error('File list inconsistent')
end

% check that the number of blocks read from the main .mat file is consistent with the number of other .mat files
nBlocksTotal = numel(parFileList);
if nBlocksTotal ~= numel(mainExpPars.blockSequence)
    error('mismatch between number of blocks from the mainExpPars file and the list of parameter files');
end

% check that the order of the blocks is consistent
countBlock = zeros(1, numel(mainExpPars.conditions));
for iB = 1:nBlocksTotal
    
    iCond           = mainExpPars.blockSequence(iB);
    expectedCond    = strrep( mainExpPars.conditions{ iCond }, ' ', '-'  );
    tag             = sprintf( '%s-block-%.2d', expectedCond, countBlock(iCond)+1 );
    countBlock(iCond) = countBlock(iCond)+1;
    
    if ~strfind(parFileList{iB}, tag)
        error('block %d: expected condition/block: %s, found file: %s', iB, tag, parFileList{iB});
    end
    
end
if unique(countBlock) ~= mainExpPars.nBlocksPerCond
    error('error in the block count!!!');
end


% filter parameters (for eog correction)
%--------------------------------------------------------------------------
filter.fr_low_margin   = .2;
filter.fr_high_margin  = 40;
filter.order           = 4;
filter.type            = 'butter'; % Butterworth IIR filter


%% =====================================================================================
%                    COMPUTER EOG CORRECTION PARAMETERS

if iEogFile
    
    % read eog calibration data file
    %--------------------------------------------------------------------------
    fprintf('\nLoading eog calibration data\n');
    hdr             = sopen( fullfile(folderName, eogCalibrationFile) );
    [sig hdr]       = sread(hdr);
    fsEogCal        = hdr.SampleRate;
    eventLoc        = hdr.EVENT.POS;
    eventType       = hdr.EVENT.TYP;
    chanListEogCal  = hdr.Label;
    chanListEogCal(strcmp(chanListEogCal, 'Status')) = [];
    
    
    % discard unused channels
    %--------------------------------------------------------------------------
    discardChanInd          = cell2mat( cellfun( @(x) find(strcmp(hdr.Label, x)), discardChanNames, 'UniformOutput', false ) );
    sig(:, discardChanInd)  = [];
    chanListEogCal(discardChanInd)= [];
    
    % re-reference EEG signals
    %--------------------------------------------------------------------------
    refChanInd  = cell2mat( cellfun( @(x) find(strcmp(hdr.Label, x)), refChanNames, 'UniformOutput', false ) );
    sig         = bsxfun( @minus, sig, mean(sig(:,refChanInd) , 2) );
    
    % filter data
    %--------------------------------------------------------------------------
    [filter.a filter.b] = butter(filter.order, [filter.fr_low_margin filter.fr_high_margin]/(fsEogCal/2));
    sig = filtfilt( filter.a, filter.b, sig );
    
    % Compute EOG regression coefficients
    %--------------------------------------------------------------------------
    fprintf('Computing EOG regression coefficients\n');
    [Bv Bh Br]  = computeEogRegCoeff(sig, eventLoc, eventType, fsEogCal, eogChan, chanListEogCal);
    
end

%% =====================================================================================
%                               TREAT OTHER FILES



hdr = sopen( fullfile(folderName, dataFile) );

statusChannel       = bitand(hdr.BDF.ANNONS, 255);
hdr.BDF             = rmfield(hdr.BDF, 'ANNONS'); % just saving up some space...
expStartStopChan    = logical( bitand(statusChannel, 1) );
expStartSamples     = find( diff(expStartStopChan) == 1 ) + 1;
expStopSamples      = find( diff(expStartStopChan) == -1 ) + 1;
refChanInd          = cell2mat( cellfun( @(x) find(strcmp(hdr.Label, x)), refChanNames, 'UniformOutput', false ) );
discardChanInd      = cell2mat( cellfun( @(x) find(strcmp(hdr.Label, x)), discardChanNames, 'UniformOutput', false ) );

% sampling rate
fs = hdr.SampleRate;
if iEogFile && fsEogCal~=fs, warning('preprocessData:fs', 'sampling rate of eog calibration file and data file are different!!'); end

% channel labels
chanList                 = hdr.Label;
chanList(strcmp(chanList, 'Status')) = [];
chanList(discardChanInd) = [];
if iEogFile && ~isequal(chanListEogCal, chanList), warning('preprocessData:chanList', 'channel list of eog calibration file and data file are different!!'); end



% check the status channel
%--------------------------------------------------------------------------
if numel(expStartSamples) ~= nBlocksTotal, error('number of experiment onsets does not match the total number of blocks'); end

% add some more checks ...........




for iC = 1:numel(mainExpPars.conditions)
    
    fprintf('\nTreating condition %d out of %d (%s)\n', iC, numel(mainExpPars.conditions), mainExpPars.conditions{iC});
    
    block       = cell(1, mainExpPars.nBlocksPerCond);
    indBlocks   = find(mainExpPars.blockSequence == iC);
    
    % some parameters
    %--------------------------------------------------------------------------

    % condition
    p3On        = mainExpPars.p3OnScen(iC);
    ssvepFreq   = mainExpPars.SsvepFreqScen(iC);    
    
    for iB = 1:mainExpPars.nBlocksPerCond
        fprintf('\tTreating block %d out of %d\n', iB, mainExpPars.nBlocksPerCond);
        
        %
        %--------------------------------------------------------------------------
        iF = indBlocks(iB);
        expParams   = load( fullfile(folderName, parFileList{iF}) );
        scenario    = xml2mat( fullfile(folderName, xmlFileList{iF}) );
        
        %
        %--------------------------------------------------------------------------
        startSample = expStartSamples(iF) - 1;
        stopSample = min( expStopSamples( expStopSamples > startSample + 1) );
        
        [sig, ~] = sread( ...
            hdr, ...
            ( stopSample - startSample + 1 ) / hdr.SampleRate, ...  % Number of seconds to read
            ( startSample-1 ) / hdr.SampleRate ...                  % second after which to start
            );       
        
        % P3 parameters
        %--------------------------------------------------------------------------
        if p3On
            % P3 stimuli index sequence
            block{iB}.p3Params.p3StateSeq = expParams.realP3StateSeqOnsets;
            
            % target state sequence (normally values between 1 and 8 evenly interspersed with 9) (or 1 and 16 evenly interspersed with 17)
            block{iB}.p3Params.targetStateSeq = expParams.lookHereStateSeq( expParams.lookHereStateSeq ~= max( expParams.lookHereStateSeq ) ); % only keep onsets
                        
        end
        
        % Event Channels
        %--------------------------------------------------------------------------
        block{iB}.statusChannel = statusChannel(startSample:stopSample);
        
        % cue event channel
        onsetEventInd           = cellfun( @(x) strcmp(x, 'Cue on'), {scenario.events(:).desc} );
        onsetEventValue         = scenario.events( onsetEventInd ).id;
        block{iB}.eventChan.cue = logical( bitand( block{iB}.statusChannel, onsetEventValue ) );

        % P300 event channel
        if p3On
            onsetEventInd               = cellfun( @(x) strcmp(x, 'P300 stim on'), {scenario.events(:).desc} );
            onsetEventValue             = scenario.events( onsetEventInd ).id;
            block{iB}.eventChan.p3      = logical( bitand( block{iB}.statusChannel, onsetEventValue ) );
        end
        
        % SSVEP event channel
        if ssvepFreq
            onsetEventInd               = cellfun( @(x) strcmp(x, 'SSVEP stim on'), {scenario.events(:).desc} );
            onsetEventValue             = scenario.events( onsetEventInd ).id;
            block{iB}.eventChan.ssvep   = logical( bitand( block{iB}.statusChannel, onsetEventValue ) );
        end    
        
        
        % discard unused channels and Re-reference
        %--------------------------------------------------------------------------------------
        sig(:, discardChanInd)  = [];
        block{iB}.sig = bsxfun( @minus, sig, mean(sig(:,refChanInd) , 2) );
        
        % additional stuffs to save (normally, not necessary)
        %--------------------------------------------------------------------------------------
        block{iB}.expParams = expParams;
        block{iB}.scenario = scenario;
        
    end
    
listOfVariablesToSave = { ...
    'hdr', ...          % normally, not necessary
    'fs', ...
    'p3On', ...
    'ssvepFreq', ...
    'chanList', ...
    'block' ...
    };    
rawFileName = fullfile( rawOutputFolder, [strrep(mainExpPars.conditions{iC}, ' ', '-') '.mat']);
fprintf('\tSaving raw data to file %s\n', rawFileName); 
save( rawFileName, listOfVariablesToSave{:} );
    

if iEogFile

    [filter.a filter.b] = butter(filter.order, [filter.fr_low_margin filter.fr_high_margin]/(fs/2));

    for iB = 1:mainExpPars.nBlocksPerCond
    %--------------------------------------------------------------------------------------
    % Preliminary filtering
    % sig = filtfilt( filter.a, filter.b, sig );
    for i = 1:size(block{iB}.sig, 2)
        block{iB}.sig(:,i) = filtfilt( filter.a, filter.b, block{iB}.sig(:,i) );
    end
    
    %--------------------------------------------------------------------------------------
    % Apply EOG correction
    block{iB}.sig = applyEogCorrection(block{iB}.sig, Bv, Br, Bh, eogChan, chanListEogCal);
    
    end
    
    %--------------------------------------------------------------------------------------
    % save eog corrected data
    eogCorrFileName = fullfile( eogCorrOutputFolder, [strrep(mainExpPars.conditions{iC}, ' ', '-') '.mat']);
    fprintf('\tSaving eog corrected data to file %s\n', eogCorrFileName);
    save( eogCorrFileName, listOfVariablesToSave{:} );
        
end

listOfVariablesToClear = listOfVariablesToSave( ~ismember( listOfVariablesToSave, {'hdr' , 'fs', 'chanList'} ) );
clear(listOfVariablesToClear{:})

end

end

