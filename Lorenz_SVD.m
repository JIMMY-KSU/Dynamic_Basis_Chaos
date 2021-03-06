clear variables; close all; clc

animRes = 0; %toggle animation of results
global_meansub = 1; %subtract global mean rather than each individual window mean


load Lorenz_sim_data.mat;
h = x.';
nSteps = size(h,2);
tStep = t(2)-t(1);


if global_meansub == 1
    h_const = mean(h,2);
    h = h-repmat(h_const,1,length(t));
end

% windows = floor(10.^(1.25:0.5:2.75));
windows = [50 100 200 2000];% 200 400];
stepSize = 1;

maxSlide = floor((nSteps - min(windows))/stepSize);
SVD_res = cell(length(windows),maxSlide);

r = 3;

for n = 1:length(windows)
    wSteps = windows(n);
    nSlide = floor((nSteps - wSteps)/stepSize);
    disp(['Running n = ' num2str(n)])
%     figure
    for k = 1:nSlide
        thisWind = (k-1)*stepSize + 1 :(k-1)*stepSize + wSteps;
        hWind = h(:,thisWind);
        if global_meansub == 0
            cWind = mean(hWind,2);
            hWind = hWind - repmat(cWind,1,length(thisWind));
            SVD_res{n,k}.cWind = cWind;
        end
        tWind = t(thisWind);
        [Uw,Sw,Vw] = svd(hWind,'econ');
        SVD_res{n,k}.U = Uw(:,1:r);
        SVD_res{n,k}.V = Vw(:,1:r);
        SVD_res{n,k}.S = diag(Sw);
%         semilogy(diag(Sw));
%         hold on
    end
%     title(['Spectra for ' num2str(wSteps*(t(2)-t(1))) ' Second Window'])
end
save('Lorenz_SVD_res.mat','SVD_res','windows','stepSize','r');

%% Compare SVD Spectra
addpath(genpath('kakearney-boundedline'));

minRank = min(min(windows),size(h,1)); %truncate all spectra to length of shortest

allMeans = zeros(length(windows),minRank); 
allStds = zeros(size(allMeans));
b = zeros(minRank,1,length(windows));


for n = 1:length(windows)
    wSteps = windows(n);
    sRank = min(wSteps,size(h,1)); %number of modes retained by econ SVD
    nSlide = floor((nSteps - wSteps)/stepSize);
    all_S = zeros(sRank,nSlide);

    for k = 1:nSlide
        all_S(:,k) = SVD_res{n,k}.S/sum(SVD_res{n,k}.S); %normalize
    end
    
    mean_S = mean(all_S,2);
    std_S = std(all_S,0,2);
    allMeans(n,:) = mean_S(1:minRank);
    allStds(n,:) = std_S(1:minRank);
    b(:,1,n) = std_S(1:minRank);
end

xBounds = [1 minRank];

% allStds = reshape(allStds,length(windows),1,min(windows)); %add singleton dimension
figure('Position',[200 200 1000 400])
subplot(1,3,1)
[h1, hp] = boundedline(1:minRank,allMeans.',b,'o');
% hold on
% plot([r r],[0 1],'r--')
legend(string(windows),'Location','best');
xlabel('Mode #');
ylabel('\sigma');
title('SVD Spectra by Window Size')
xlim(xBounds);
subplot(1,3,2)
[h1L, hpL] = boundedline(1:minRank,allMeans.',b,'o');
set(gca,'YScale','log')
% hold on
% plot([r r],ylim,'r--')
legend(string(windows),'Location','best');
xlabel('Mode #');
ylabel('\sigma');
title('SVD Spectra by Window Size (Log Scale)')
xlim(xBounds);
subplot(1,3,3)
plot(cumsum(allMeans.'),'o-')
% hold on
% plot([r r],[0 1],'r--')
hold on
plot(1:size(allMeans,2),ones(size(allMeans,2),1),'k:');
xlim(xBounds);
xlabel('Mode #');
ylabel('\Sigma\sigma');
legend(string(windows),'Location','best');
hold off
title('SVD Spectra - Cumulative Sums')

%% Correct for mode sign flips
for n = 1:length(windows)
    wSteps = windows(n);
    nSlide = floor((nSteps - wSteps)/stepSize);
    V_old = SVD_res{n,1}.V;
    U_old = SVD_res{n,1}.U;
    for k = 2:nSlide
        V_wind = SVD_res{n,k}.V;
        U_wind = SVD_res{n,k}.U;
        updateRes = 0;
        for j = 1:r
            if norm(U_wind(:,j) - U_old(:,j)) > norm(U_wind(:,j) + U_old(:,j))
                U_wind(:,j) = -U_wind(:,j);
                V_wind(:,j) = -V_wind(:,j);
                updateRes = 1;
            end
        end
        if updateRes == 1
            SVD_res{n,k}.V = V_wind;
            SVD_res{n,k}.U = U_wind;
        end
        V_old = V_wind;
        U_old = U_wind;
    end
end

%% Moving Window SVD Reconstruction

tBounds = [1 5]; %default plot limits

h_recons = cell(length(windows),1); 
V_full_all = cell(length(windows),1);
V_full_discr_all = cell(length(windows),1);
x_full_discr_all = cell(length(windows),1);
t_discr_all = cell(length(windows),1);
allModes = cell(length(windows),1);
windMids_all = cell(length(windows),1);

for n = 1:length(windows)
    wSteps = windows(n);
    nSlide = floor((nSteps - wSteps)/stepSize);
    
    h_recon = zeros(size(h));
    V_full = zeros(r,length(t)); %moving weighted average of mode projections
    V_full_discr = zeros(nSlide,r); %mean values of mode projections for each window
    x_full_discr = zeros(nSlide,size(h,1)); %mean values of mode projections for each window
    t_discr = zeros(1,nSlide);
    wModes = zeros(nSlide,r,size(h,1)); %window step #, mode #, mode vector
    wSVs = zeros(nSlide,r); %singular values over time
    
    wCount = zeros(size(t)); %count # windows contributing to each step
    windMids = zeros(nSlide,1);
    disp(['Running n = ' num2str(n)])
    
    for k = 1:nSlide
        thisWind = (k-1)*stepSize + 1 :(k-1)*stepSize + wSteps;
        t_discr(k) = t(thisWind(end));
        x_full_discr(k,:) = h(:,thisWind(end)).';
        windMid = (k-1)*stepSize + floor(wSteps/2);
        windMids(k) = windMid;
        V_wind = SVD_res{n,k}.V(:,1:r);
        U_wind = SVD_res{n,k}.U(:,1:r);
        S_wind = SVD_res{n,k}.S(1:r);
        V_full(:,thisWind) = V_full(:,thisWind) + V_wind.';
        h_recon(:,thisWind) = h_recon(:,thisWind) + U_wind * diag(S_wind) * V_wind.';
        if global_meansub == 0
            h_recon(:,thisWind) = h_recon(:,thisWind) + repmat(SVD_res{n,k}.cWind,1,length(thisWind));
        end
        wCount(thisWind) = wCount(thisWind) + 1;
        wModes(k,:,:) = U_wind.';
%         V_full_discr(k,:) = mean(V_wind,1);
        V_full_discr(k,:) = V_wind(end,:);
        wSVs(k,:) = S_wind;
    end
    thetas = zeros(nSlide,r);
    phis = zeros(nSlide,r);
    % Extract spherical coord. angles
    for k = 1:nSlide
        for j = 1:r
            mv = squeeze(wModes(k,j,:));
            [phi, theta, ~] = cart2sph(mv(1),mv(2),mv(3));
            thetas(k,j) = theta;
            phis(k,j) = phi;
        end
    end
    h_recon = h_recon./repmat(wCount,size(h,1),1);
%     if global_meansub == 1
%         h_recon = h_recon + repmat(h_const,1,size(h,2));
%     end

    V_full = V_full./repmat(wCount,r,1);
    
    h_recons{n} = h_recon;
    t_discr_all{n} = t_discr;
    V_full_all{n} = V_full;
    V_full_discr_all{n} = V_full_discr;
    x_full_discr_all{n} = x_full_discr;
    allModes{n} = wModes;
    windMids_all{n} = windMids;
    
    figure
    subplot(3,2,1:2)
    plot(t,h(1:r,:),'k-')
    hold on
    plot(t,h_recon(1:r,:),'r-')
    hold on
    plot(1.1*tBounds(1) + wSteps*(t(2)-t(1))*[0 1],1.1*max(max(h(1:2,:)))*[1 1],'b-')
    hold off
    title(['Reconstruction: ' num2str(wSteps*(t(2)-t(1))) 's window'])
    xlim(tBounds);
    
    subplot(3,2,3)
%     plot(t,V_full)
%     hold on
    plot(windMids*(t(2)-t(1)),V_full_discr,'o-','MarkerSize',1)
    title('Time Series, SVD Basis')
    xlim(tBounds);
    
    subplot(3,2,4)
    plot(windMids*(t(2)-t(1)),wSVs)
    title('Singular Values over Time');
    xlim(tBounds);
    
    subplot(3,2,5)
    plot(windMids*(t(2)-t(1)), thetas)
    title('Mode \theta Coords')
    xlim(tBounds);
    ylim([-pi/2 pi/2])
    yticks(pi*(-1/2 : 1/4: 1/2));
    set(gca,'YTickLabel', {'-\pi/2','-\pi/4','0','\pi/4','\pi/2'});
    
    subplot(3,2,6)
    plot(windMids*(t(2)-t(1)), phis)
    title('Mode \phi Coords')
    xlim(tBounds);
    ylim([-pi pi])
    yticks(pi*(-1 : 1/2: 1));
    set(gca,'YTickLabel', {'-\pi','-\pi/2','0','\pi/2','\pi'});
end

outFile = 'Lorenz_sindy_input.mat';
save(outFile, 'V_full_discr_all', 'x_full_discr_all','t_discr_all','windows');

%% Mode Angles

% for n = 1:length(windows)
%     wSteps = windows(n);
%     nSlide = floor((nSteps - wSteps)/stepSize);
%     mAngles = zeros(nSlide-1,r);
%     for k = 1:nSlide-1
%         for j = 1:r
%             u1 = SVD_res{n,k}.U(:,j);
%             u2 = SVD_res{n,k+1}.U(:,j);
%             mAngles(k,j) = acos(dot(u1,u2));
%         end
%     end
%     figure
%     plot(mAngles)
%     title(['Rotation Angles for ' num2str(wSteps) '-Step Window'])
% end

return;

%% Animate results
% dims = randperm(size(h,1),3); %pick some dimensions to display
dims = [1 2 3];
tailLength = 25;
sAlpha = 0.1; %transparency of backdrop attractor


figure('Position',[100 50 1200 650])
n = 4; %which window size to show
wSteps = windows(n);
windMids = windMids_all{n};
dispModes = allModes{n}(:,:,dims); %step #, mode #, mode coord
dispModes = dispModes./repmat(sqrt(sum(dispModes.^2,3)),1,1,3);
h_recon = h_recons{n};

subplot(4,3,[1 4])
if global_meansub == 1
%     cShift = h_const;
    cShift = zeros(size(h_const));
else
    cShift = SVD_res{n,1}.cWind;
end
axPlot = plot3(100*[-squeeze(dispModes(1,:,1)); squeeze(dispModes(1,:,1))]+cShift(1),...
    100*[-squeeze(dispModes(1,:,2)); squeeze(dispModes(1,:,2))]+cShift(2),...
    100*[-squeeze(dispModes(1,:,3)); squeeze(dispModes(1,:,3))]+cShift(3),'LineWidth',2);
hold on
plot3([-1 0 0; 1 0 0], [0 -1 0; 0 1 0], [0 0 -1; 0 0 1],'k:')       
hold on
hPlotB = plot3(h(dims(1),thisWind),h(dims(2),thisWind),h(dims(3),thisWind),'k-','LineWidth',3);
hold on
hShadowPlot = plot3(h(dims(1),:),h(dims(2),:),h(dims(3),:),'k');
for j = 1:size(dims)
    hShadowPlot(j).Color = [0,0,0,sAlpha];
end
hold off
xlim(1.1*[min(h(dims(1),:)) max(h(dims(1),:))]);
ylim(1.1*[min(h(dims(2),:)) max(h(dims(2),:))]);
zlim(1.1*[min(h(dims(3),:)) max(h(dims(3),:))]);
title('SVD Basis: Proj. 3D');
xlabel(['Dim. ' num2str(dims(1))]);
ylabel(['Dim. ' num2str(dims(2))]);
zlabel(['Dim. ' num2str(dims(3))]);

subplot(4,3,[2 5])
% V_full = V_full_all{n};
% noNaN = ~isnan(V_full(1,:));
% V_full = V_full(:,noNaN);
% t_full = t(noNaN);
V_full_discr = V_full_discr_all{n};
thisWind = 1:windows(n);
% vPlot = plot3(V_full(1,thisWind),V_full(2,thisWind),V_full(3,thisWind),'LineWidth',1);
vPlot = plot3(V_full_discr(1,1),V_full_discr(2,1),V_full_discr(3,1),'bo');
hold on
vTail = plot3(V_full_discr(1,1),V_full_discr(2,1),V_full_discr(3,1),'b-');
vTail.Color = [0,0,0,sAlpha];
hold off
xlabel('SVD Mode 1');
ylabel('SVD Mode 2');
zlabel('SVD Mode 3');
% xlim(mean(V_full(1,:)) + 2*std(V_full(1,:))*[-1 1]);
% ylim(mean(V_full(2,:)) + 2*std(V_full(2,:))*[-1 1]);
% zlim(mean(V_full(3,:)) + 2*std(V_full(3,:))*[-1 1]);
xlim([min(V_full_discr(:,1)) max(V_full_discr(:,1))]);
ylim([min(V_full_discr(:,2)) max(V_full_discr(:,2))]);
zlim([min(V_full_discr(:,3)) max(V_full_discr(:,3))]);

title({['t = ' num2str(windMids(1)*(t(2)-t(1)))],'Avg. Position in SVD Basis Over Window'})
% xlim([t(thisWind(1)),t(thisWind(end))]);
% hold on
% yl = ylim;
% windBar = plot([1 windows(n)]*(t(2)-t(1)), [yl(1) yl(1)],'r-','LineWidth',4);
subplot(4,3,[3 6])
% gca.ColorOrderIndex = 4;
hPlot = plot(tStep*thisWind,h(:,thisWind)); 
xlim(tStep*[windMids(1) windMids(end)]);
xlabel('t');
ylabel('Coords in XYZ Basis');

subplot(4,3,[9 12])
vtPlot = plot(tStep*windMids(1),V_full_discr(1,:));
xlim(tStep*[windMids(1) windMids(end)]);
xlabel('t');
ylabel('Coords in SVD Basis');

subplot(4,3,7:8)
thPlot = plot(tStep*windMids(1),thetas(1,:));
ylabel('\theta');
xlim(tStep*[windMids(1) windMids(end)]);
yticks(pi*(-1/2 : 1/4: 1/2));
set(gca,'YTickLabel', {'-\pi/2','-\pi/4','0','\pi/4','\pi/2'});

subplot(4,3,10:11)
phiPlot = plot(tStep*windMids(1),phis(1,:));
legend({'Mode 1', 'Mode 2', 'Mode 3'})
ylabel('\phi');
xlabel('t');
xlim(tStep*[windMids(1) windMids(end)]);
yticks(pi*(-1 : 1/2: 1));
set(gca,'YTickLabel', {'-\pi','-\pi/2','0','\pi/2','\pi'});

for k = 2:nSlide
    thisWind = (k-1)*stepSize + 1 :(k-1)*stepSize + wSteps;
    subplot(4,3,[2 5])
    title({['t = ' num2str(windMids(k)*tStep)],'Avg. Position in SVD Basis Over Window'})
    
    
    
    for j = 1:3
        if global_meansub == 0
            cShift = SVD_res{n,k}.cWind;
        end
        axPlot(j).XData = 100*[-squeeze(dispModes(k,j,1)); squeeze(dispModes(k,j,1))]+cShift(1);
        axPlot(j).YData = 100*[-squeeze(dispModes(k,j,2)); squeeze(dispModes(k,j,2))]+cShift(2);
        axPlot(j).ZData = 100*[-squeeze(dispModes(k,j,3)); squeeze(dispModes(k,j,3))]+cShift(3);
        
        haxPlot(j).XData = 100*[-squeeze(dispModes(k,j,1)); squeeze(dispModes(k,j,1))]+cShift(1);
        haxPlot(j).YData = 100*[-squeeze(dispModes(k,j,2)); squeeze(dispModes(k,j,2))]+cShift(2);
        haxPlot(j).ZData = 100*[-squeeze(dispModes(k,j,3)); squeeze(dispModes(k,j,3))]+cShift(3);
        
        thPlot(j).XData = [thPlot(j).XData tStep*windMids(k)];
        thPlot(j).YData = [thPlot(j).YData thetas(k,j)];
        
        phiPlot(j).XData = [phiPlot(j).XData tStep*windMids(k)];
        phiPlot(j).YData = [phiPlot(j).YData phis(k,j)];
        
        hPlot(j).XData = [hPlot(j).XData tStep*thisWind];
        hPlot(j).YData = [hPlot(j).YData h(dims(j),thisWind)];
        
        vtPlot(j).XData = [vtPlot(j).XData tStep*windMids(k)];
        vtPlot(j).YData = [vtPlot(j).YData V_full_discr(k,j)];
    end
    
    
%     vPlot.XData = V_full(1,thisWind);
%     vPlot.YData = V_full(2,thisWind);
%     vPlot.ZData = V_full(3,thisWind);

    vPlot.XData = V_full_discr(k,1);
    vPlot.YData = V_full_discr(k,2);
    vPlot.ZData = V_full_discr(k,3);
    
%     if length(vTail.XData) <= tailLength
        vTail.XData = [vTail.XData V_full_discr(k,1)];
        vTail.YData = [vTail.YData V_full_discr(k,2)];
        vTail.ZData = [vTail.ZData V_full_discr(k,3)];
%     else
%         vTail.XData = [vTail.XData(2:end) V_full_discr(k,1)];
%         vTail.YData = [vTail.YData(2:end) V_full_discr(k,2)];
%         vTail.ZData = [vTail.ZData(2:end) V_full_discr(k,3)];
%     end
    
    
    
    hPlotB.XData = h(dims(1),thisWind);
    hPlotB.YData = h(dims(2),thisWind);
    hPlotB.ZData = h(dims(3),thisWind);

    hrPlot.XData = h_recon(dims(1),thisWind);
    hrPlot.YData = h_recon(dims(2),thisWind);
    hrPlot.ZData = h_recon(dims(3),thisWind);
    
    
    if animRes == 1
        pause(0.01);
    end
end