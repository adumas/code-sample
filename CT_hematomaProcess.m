function [TIME1 TIME2] = CT_hematomaProcess(subject)
%% misc
func_name = 'CT_hematomaProcess';
if nargin < 1, subject='2032272'; end
%addpath('/autofs/space/lang_012/users/FREESURFER_HOME_CVRAM/stable4/matlab');
addpath('/autofs/cluster/freesurfer/centos4.0_x86_64/stable5/matlab');
%% read files
fprintf(1,'%s: read volumes ',func_name);
t=tic;
floc=fullfile('/autofs/cluster/ichresearch/Hematoma/Coreg_spot_sign',subject);
tp1_fspec = '01_tp.nii.gz';
tp2_fspec = 'rf02_tp.nii.gz';
tp1_loc=fullfile(floc,tp1_fspec);
tp2_loc=fullfile(floc,tp2_fspec);

[T first] = evalc('MRIread(tp1_loc)');
[T second] = evalc('MRIread(tp2_loc)');

%copy MRIread volumes to structures
tp1 = first;
tp2 = second;
tt=toc(t);
fprintf(1,'... done (%2.1f s)\n',tt);
if 1; %~exist(fullfile(floc,[subject '_data.mat']),'file'),
%% manually ID hematoma slice-by-slice
if ~exist(fullfile(floc,'tp1.mat'),'file'),
    hmont = immontage(tp1.vol,[1000 1100],'gray',1);
    [tp1.mask tp1.points]=ct_manualICH(tp1.vol);
    save(fullfile(floc,'tp1.mat'),'tp1');
else
    load(fullfile(floc,'tp1.mat'));
end

if ~exist(fullfile(floc,'tp2.mat'),'file'),
    hmont = immontage(tp2.vol,[1000 1100],'gray',1);
    [tp2.mask tp2.points]=ct_manualICH(tp2.vol);
    save(fullfile(floc,'tp2.mat'),'tp2');
else
    load(fullfile(floc,'tp2.mat'));
end

mri = first;
mri.vol = tp1.mask;
MRIwrite(mri,fullfile(floc,['01_manualICHmask_tp.nii.gz']));
mri = second;
mri.vol = tp2.mask;
MRIwrite(mri,fullfile(floc,['02_manualICHmask_tp.nii.gz']));

close all;

%keyboard
%% mask brain by removing skull (thresholding)
fprintf(1,'%s: skull-stripping ',func_name);
t=tic;

tp1.brainmask = ct_skullstrip(tp1.vol);
fprintf(1,'... 1 ');
tp2.brainmask = ct_skullstrip(tp2.vol);
fprintf(1,'... 2 ');

tp1.brain = tp1.brainmask .* tp1.vol;
tp2.brain = tp2.brainmask .* tp2.vol;
tt=toc(t);
fprintf(1,'... done (%2.1f s)\n',tt);

%% normalize parenchyma
fprintf(1,'%s: normalize parenchyma ',func_name);
t=tic;

tp1.normBrain = ct_normalize(tp1.brain);
tp2.normBrain = ct_normalize(tp2.brain);
tt=toc(t);
fprintf(1,'... done (%2.1f s)\n',tt);

%% contrast enhancement (histogram thresholding)
fprintf(1,'%s: contrast enhance',func_name);
t=tic;

tp1.enhanced = ct_enhance(tp1.normBrain);
tp2.enhanced = ct_enhance(tp2.normBrain);
fprintf(1,', writing files');
mri = first;
mri.vol = tp1.enhanced;
MRIwrite(mri,fullfile(floc,['e' tp1_fspec]));
mri = second;
mri.vol = tp2.enhanced;
MRIwrite(mri,fullfile(floc,['e' tp2_fspec]));
fprintf(1,'... done (%2.1f s)\n',tt);

%% EM segmentation (VERY experimental)
% fprintf(1,', EM segmentation');
% [y msg] = system(sprintf('/usr/local/freesurfer/stable5_0_0/bin/mri_ms_EM -M 8 -conform %s %s',fullfile(floc,['e' tp1_fspec]),fullfile(floc,'tp1_')));
% [y msg] = system(sprintf('/usr/local/freesurfer/stable5_0_0/bin/mri_ms_EM -M 8 -conform %s %s',fullfile(floc,['e' tp2_fspec]),fullfile(floc,'tp2_')));
% tt=toc(t);
else
    load(fullfile(floc,[subject '_data.mat']));
end

%% Region Growing Segmentation using points (experimental)
fprintf(1,'%s: region growing using points...',func_name);
t=tic;

tp1.regionSeg = ct_regionGrow(tp1.enhanced,tp1.points);
%%
fprintf(1,'... 1 ');
tp2.regionSeg = ct_regionGrow(tp2.enhanced,tp2.points);
fprintf(1,'... 2 ');

tt=toc(t);
fprintf(1,'... done (%2.1f s)\n',tt);

%% otsu thresholding for hematoma
fprintf(1,'%s: otsu threshold segmentation ',func_name);
t=tic;

tp1.threshSeg = ct_otsu(tp1.enhanced);
tp2.threshSeg = ct_otsu(tp2.enhanced);
tt=toc(t);
fprintf(1,'... done (%2.1f s)\n',tt);

%% k-means clustering for hematoma
fprintf(1,'%s: k-means segmentation ',func_name);
t=tic;

tp1.kSeg = ct_kmeans(tp1.enhanced);
tp2.kSeg = ct_kmeans(tp2.enhanced);
tt=toc(t);
fprintf(1,'... done (%2.1f s)\n',tt);

%%
% newseg = seg == 2;
% CC = bwconncomp(newseg,6);
% S = regionprops(CC,'Area');
% ss=[];
% for z=1:numel(S), ss(z) = S(z).Area; end
% [y ind] = max(ss);
% newseg(CC.PixelIdxList{ind}) = 2;
%% imclose seg to remove smaller items and verify 3D connectivity
fprintf(1,'%s: erode/dilate mask(s) ',func_name);
t=tic;

tp1.ich = ct_ichmask(tp1.threshSeg.*tp1.mask);
tp2.ich = ct_ichmask(tp2.threshSeg.*tp1.mask);
tt=toc(t);
fprintf(1,'... done (%2.1f s)\n',tt);

%% any kind of manual error-checking
% going through slice by slice to identify hematoma approx. centroid
% automated vs. manual spot-sign identification

%% overlays for tp1, tp2 and overlap
both.overlap = tp2.ich & tp1.ich;
both.diff = tp2.ich - tp1.ich;

%figure; clear img; img(:,:,1,:) = (tp2.ich); montage(img,'DisplayRange',[])

% for i = 1:size(seg,3),
%     ich(:,:,:,i) = label2rgb(seg(:,:,i));
% end
% hold on;
% zimg=montage(ich);
% set(zimg,'AlphaData',0.1);

%% visualize results and save
fprintf(1,'%s: saving data ',func_name);
save(fullfile(floc,[subject '_data.mat']),'tp1','tp2');
fprintf(1,'... done\n');

if nargout > 0,
    TIME1 = tp1;
    TIME2 = tp2;
end
end

function [mask points]=ct_manualICH(I)
%%
[nx ny nz] = size(I);
h_fig = figure;
%set(h_fig,'KeyPressFcn',@(h_obj,evt) disp(evt.Key));
mask = zeros(size(I));
for z=1:nz
    him = imagesc(I(:,:,z),[1000 1100]); axis off; axis image; colormap bone;
    if z ==1,
        set(gcf,'Units','pixels');
        pos = get(gca,'Position');
        shim = 80;
        set(gcf,'Position',[pos(1) pos(2) size(I,1)+shim size(I,2)+shim]);
        set(gca,'Units','pixels');
        pos = get(gca,'Position');
        width = pos(3);
        height = pos(4);
        set(gca,'Position',[shim/2 shim/2 size(I,1) size(I,2)]);
        set(gca, 'xlimmode','manual',...
            'ylimmode','manual',...
            'zlimmode','manual',...
            'climmode','manual',...
            'alimmode','manual');
        set(gcf,'doublebuffer','off');
    end
    title('Select approximate centroid of hematoma on this slice... (ENTER to continue)');
    htxt = text('units','pixels','position',[2 0],'fontsize',72,'string',num2str(z),'VerticalAlignment','bottom','HorizontalAlignment','left','color','w');
    [x{z}, y{z}] = getpts;
    hold on;
    delete(him);
    delete(htxt);
end
for z=1:nz
    if ~isempty(x{z})
        him = imagesc(I(:,:,z),[1000 1100]); axis image; colormap bone; drawnow;
        htxt = text('units','pixels','position',[0 0],'fontsize',56,'string',num2str(z),'VerticalAlignment','bottom','HorizontalAlignment','left','color','w');
        hold on;
        plot(x{z},y{z},'gsquare');
        pts(z).x = x{z};
        pts(z).y = y{z};
        if z ==1,
            set(gcf,'Units','pixels');
            pos = get(gca,'Position');
            shim = 80;
            set(gcf,'Position',[pos(1) pos(2) size(I,1)+shim size(I,2)+shim]);
            set(gca,'Units','pixels');
            pos = get(gca,'Position');
            width = pos(3);
            height = pos(4);
            set(gca,'Position',[shim/2 shim/2 size(I,1) size(I,2)]);
            set(gca, 'xlimmode','manual',...
                'ylimmode','manual',...
                'zlimmode','manual',...
                'climmode','manual',...
                'alimmode','manual');
            set(gcf,'doublebuffer','off');
        end
        title('Freehand select hematoma borders... (DOUBLE CLICK to continue)')
        h = imfreehand(gca);
        position = wait(h);
        mask(:,:,z) = createMask(h,him);
        
        pause(0.1)
        delete(him);
        delete(h);
        delete(htxt);
    else
        pts(z).x = 0;
        pts(z).y = 0;
    end
    
end
points=(pts);
end

function [points]=ct_OLDmanualICH(I)
%%
[nx ny nz] = size(I);
h_fig = figure;
set(h_fig,'KeyPressFcn',@(h_obj,evt) disp(evt.Key));

for z=1:nz
    him = imshow(I(:,:,z),[1000 1100]);
    [x, y] = getpts;
    hold on;
if ~isempty(x)
    plot(x,y,'gsquare');
    pts(z,:) = [x y];
    pause(0.05)
else
    pts(z,:) = [0 0];
end

end
points=(pts);
end

function brainmask = ct_skullstrip(I)
% mask brain by removing skull (thresholding)
% threshold out skull
%%
mask=(I > 1000) .* (I < 1100);
mask(:,:,1:7)=0;

%evaluate 3D connectivity on slice and adjacent slices
% "a"-vars are lookahead
% "b"-vars are lookbehind
newmask = mask;
for i = size(mask,3)-1:-1:2,
    %%
    %fprintf(1,'%d, %d\n',i,i+1); % some progress
    
    abm = mask(:,:,i:i+1); %select slice and slice after
    bbm = mask(:,:,i-1:i); %select slice and one before
    
    %find connectivity and area of connected regions
    aCC = bwconncomp(abm,6);
    bCC = bwconncomp(bbm,6);
    aS = regionprops(aCC,'Area');
    bS = regionprops(bCC,'Area');
    ssa=[];
    ssb=[];
    
    %find areas and select max area
    %(works best in cortex and some of cerebellum)
    for z=1:numel(aS), ssa(z) = aS(z).Area; end
    for z=1:numel(bS), ssb(z) = bS(z).Area; end
    
    %ssa = cat(1,aS.Area);
    %ssb = cat(1,bS.Area);
    [y aind] = max(ssa);
    [y bind] = max(ssb);
    
    %logical indexing to make good/overlap regions to value of 2
    abm(aCC.PixelIdxList{aind}) = 2;
    bbm(bCC.PixelIdxList{bind}) = 2;
   
    %select all area where pixels > 2
    newmask(:,:,i) = (abm(:,:,1) > 1) & (bbm(:,:,2) > 1);  
end
%%
%Now, evaluate 3d connectivity over all slices, and remove small holes

%3d connectivity
CC = bwconncomp(newmask,6);
S = regionprops(CC,'Area');
ss=[];
for z=1:numel(S), ss(z) = S(z).Area; end
[y ind] = max(ss);
newmask(CC.PixelIdxList{ind}) = 2;

%%
brainmask = newmask > 1;
%clear img; img(:,:,1,:) = brainmask; montage(img,'DisplayRange',[])

% erode skullmask so that it removes ever-so-slightly the parenchyma near
% skull to be sure
sel = strel('disk',4);
SE = strel('disk',5,0);

for i = 1:size(brainmask,3),
    %brainmask(:,:,i) = imerode(brainmask(:,:,i),sel); %erode
    %brainmask(:,:,i) = imfill(brainmask(:,:,i),'holes'); %fill holes
    brainmask(:,:,i) = imopen(newmask(:,:,i),SE); %use imopen to remove segments smaller than SE strel
    brainmask(:,:,i) = imfill(brainmask(:,:,i),'holes'); %fill holes
    %brainmask(:,:,i) = imerode(brainmask(:,:,i),sel); %erode
end

%% 3d connectivity
CC = bwconncomp(brainmask,6);
S = regionprops(CC,'Area');
ss=[];
for z=1:numel(S), ss(z) = S(z).Area; end
[y ind] = max(ss);

bm=zeros(size(brainmask));
bm(CC.PixelIdxList{ind}) = 1;
ext_mask = ~(sum(bm,3) < 2);

bm = bm .* repmat(ext_mask, [1 1 size(bm,3)]);
% for i = 1:size(brainmask,3),
%     brainmask(:,:,i) = imdilate(bm(:,:,i),sel); %erode
% end

end

function norm = ct_normalize(I)
%%
%CT_normalize to 0-100 range in parenchyma (might need more robustness...)
old = I;
norm = old;
level = 1000;
window = 100;

old(old < level) = level;
old(old > (level+window)) = (level+window);
old = old - level;
norm = old .* (old > 0);

end

function norm = ct_enhance(I)
%%
%use hist & imadjust
norm = zeros(size(I));
for slice = 1:size(I,3),
    img = mat2gray(I(:,:,slice));
    if nnz(img(:)) > 0,
        [N X] = hist(img(img > 0 & img < 1),100);
        [y ind] = max(N);                       % find peak in hist
        J = imadjust(img,[X(ind) 0.85],[0 1]);   % adjust from histogram peak
        K = medfilt2(J);                        % median filter to remove graniness
        norm(:,:,slice) = K;
    end
end

end

function seg = ct_regionGrow(I,pts)
%%
%region growing on hematoma using points
seg = zeros(size(I));
n=0;
for slice = 1:size(I,3)
    img = I(:,:,slice);
    if pts(slice).x(1) > 0 && pts(slice).y(1) > 0,
        n=n+1;
        aseed(n,:) = [pts(slice).x(1) pts(slice).y(1) slice];
    end
end
seed = round(mean(aseed));
x = seed(1);
y = seed(2);
z = seed(3);
thresh = 0.05;

[J iter_wall] = regiongrowing_3d(I,x,y,z,thresh,Inf,1);

end

function seg = ct_otsu(I)
%%
%threshold image slice by slice using otsu via im2bw
seg = zeros(size(I));
for slice = 1:size(I,3)
    img = I(:,:,slice);
    if nnz(img(:)) > 0,
        [seg(:,:,slice)] = im2bw(img);
        %fprintf(1,'%d ... done\n',slice);
    end
end
end

function seg = ct_kmeans(I,nk)
%%
parallelStart();

if nargin < 2, nk = 3; end
seg = zeros(size(I));
parfor slice = 1:size(I,3)
    %%
    img = I(:,:,slice);
    if nnz(img(:)) > 300,
        [mu seg(:,:,slice) iterations] = img_kmeans(im2uint8(img),nk);
        %[seg(:,:,slice),mu(slice,:),v,p] = EMSeg(im2uint8(img),nk);
        fprintf(1,'%2.0f done (%4.0f iterations)\n',slice,iterations);
    end
end

end

function qseg = ct_ichmask(seg)
%% imclose to remove smaller items

SE = strel('disk',4);
nseg = seg;
for i = 1:size(seg,3),
    nseg(:,:,i) = imclose(seg(:,:,i),SE);
end

qseg = nseg;

%nseg(nseg < 4) = 0;

% %% verify 3D connectivity of hematoma mask
% % evaluate 3d connectivity and return largest 3d-connected object (ICH)
% CC=bwconncomp(nseg,6);
% S = regionprops(CC,'Area');
% ss=[];
% for z=1:numel(S), ss(z) = S(z).Area; end
% [y ind] = max(ss);
% qseg = zeros(size(nseg));
% qseg(CC.PixelIdxList{ind}) = 1;
end

function [] = parallelStart()
%%
host=getenv('HOST');
if ~any([strfind(host,'compute')])
    if strcmp(host,'eesmith'), nCores=2;
    elseif strcmp(host,'orion'), nCores=4;
    elseif strcmp(host,'batmri'), nCores=2;
    else nCores=2;
    end
    
    isOpen = matlabpool('size') > 0;
    if isOpen ~= 1,
        T = evalc('matlabpool(''open'', nCores)');
    elseif matlabpool('size') ~= nCores
        T = evalc('matlabpool(''close'')');
        T = evalc('matlabpool(''open'', nCores)');
    end
end
%fprintf(1,'using %d cores on %s...\n',matlabpool('size'),host);
end