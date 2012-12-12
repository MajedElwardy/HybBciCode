function [sig chanList] = reorderEEGChannels(sig, chanList)

if ~iscell(sig), sig = {sig}; end

nChan = unique( cellfun(@(x) size(x, 2), sig) );
if numel(nChan) ~= 1, error('all signals do not have the same amount of channels'); end
if nChan ~= numel(chanList), error('the number of signals and channel labels do not match'); end

reorderedChannels = {...
                 'Fp1',   'Fp2', ...               
               'AF3',       'AF4', ...
...              
      'F7',   'F3',   'Fz',   'F4',   'F8', ...
...     
        'FC5',   'FC1',   'FC2',   'FC6', ...
...        
    'T7',    'C3',    'Cz',    'C4',    'T8', ...
...    
        'CP5',   'CP1',   'CP2',   'CP6', ...
...
      'P7',   'P3',   'Pz',   'P4',   'P8', ...
...     
               'PO3',       'PO4', ...
                'O1', 'Oz', 'O2' ...
    };

nChansToReorder = numel( reorderedChannels );

if sum( ismember(chanList(1:nChansToReorder), reorderedChannels) ) ~= nChansToReorder
    error('the %d first channel labels do not match with the reordered channels list', nChansToReorder)
end


iCh = cell2mat(cellfun(@(x) find(strcmp(chanList, x)), reorderedChannels, 'UniformOutput', false));
sig = cellfun(@(x) [ x(:,iCh) x(:, nChansToReorder+1:end) ], sig, 'UniformOutput', false);
chanList = [reorderedChannels' ; chanList(nChansToReorder+1:end)];
