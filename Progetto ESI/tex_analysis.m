clear
close all
clc



%% --- IMPOSTAZIONI

% ---- Scelta dell'input e gestione files
analyze_just_one = true; % Se true, analizza una sola immagine;
% altrimenti analizza tutta la cartella

rand_image = false; % Se true e se analyze_just_one è true, sceglie
% randomicamente l'immagine da analizzare.
% Altrimenti sceglie la unrand_number-esima.

unrand_number = 90;  % Se rand_image è false, seleziona l'immagine.

flush_folder=false; % Se true, svuota la cartella result prima
% di iniziare

% ---- Impostazioni di risultato
show_resume = true;  % se true apre la figura di riassunto coi passaggi

show_resume_choice = false; %considerto solo se show_resume è true; mostra
% sia la mappa CONT che la CORR.

show_result = false; % se true apre una figura che mostra la zona
% selezionata
kernel_amount = 50;

% ---- Parametri per l'analisi
disk_dim = 5;% Specifica la dimensione da usare per la open della maschera
areaopen = 300; % Specifica l'area minima selezionabile.

%% --- RUN


%% Caricamento files

% ---- Gestione cartella risultati
if not(isfolder('results'))
    mkdir('results')
end

if flush_folder == true
    delete('results\*')
end

% ---- Caricamento tutte le immagini
files = dir('defect_images\*.jpg');

% ---- Gestione di _quali_ immagini analizzare (secondo le impostazioni)
to_be_analyzed = length(files);
if analyze_just_one == true
    to_be_analyzed = 1;
else
    rand_image = false;
end


kernel_types = ["CORR","CONT"]; %mi serve solo per avere le stringhe pronte comode

% for loop for each file in folder:
for fn=1:to_be_analyzed
    i=fn;
    [IMG_RGB, filename]= fileloader(fn,files,analyze_just_one,rand_image,unrand_number);
    IMG = rgb2gray(IMG_RGB); % 512x512
    [IMG_x,IMG_y]=size(IMG);
    
    %% - Analisi
    
    % --- Ricerca dimensione ottimale dei kernels

    % Salva le due pattern size ideali trovate dalla funzione apposita,
    % per provarle in sequenza.
    [kernel_corr, kernel_cont]  = find_pattern_size(IMG);
    kernels = [kernel_corr, kernel_cont];
    
    
    % L'analisi base (xcorr) viene fatta due volte: una usando il kernel
    % che massimizza CORR e una usando quello che massimizza CONT. Poi si
    % decide quale delle due maschere è più bella.
    for k_a=1:2
        
        kernel_dim = kernels(k_a);
        kernel_type = kernel_types(k_a);
        fprintf('A.%d) Kernel %s scelto : %d\n',k_a,kernel_type,kernel_dim);
        
        % ---- Genero la xcorr "di base" dove farò la media di tutte le altre
        xcorr_full = zeros(IMG_x + kernel_dim-1, IMG_y + kernel_dim-1);
        
        % Zona massima considerabile (non voglio pescare kernel fuori
        % dalla zona)
        pat_x_max = IMG_x - kernel_dim;
        pat_y_max = IMG_y - kernel_dim;
        
        % genero il posto dove salverò le posizioni dei kernel
        if k_a ==1
            kern_pos_corr=cell(1,kernel_amount);
        else
            kern_pos_cont=cell(1,kernel_amount);
        end
        
        for krn=1:kernel_amount
            % Estraiamo a sorte le posizioni del pattern. Consideriamo
            % solamente posizioni che si trovano negli angolini
            % dell'immagine, perché spesso e volentieri il difetto è in
            % mezzo
            
            while true
                pat_x = randi(pat_x_max);
                if pat_x < IMG_x/4 || pat_x > (IMG_x - IMG_x/4)
                    break;
                end
            end
            while true
                pat_y = randi(pat_y_max);
                if pat_y < IMG_y/4 || pat_y > (IMG_y - IMG_y/4)
                    break;
                end
            end
            
            %Salviamo le coordinate estratte nelle celle rispettive
            if k_a ==1
                kern_pos_corr{krn}=[pat_x, pat_y];
            else
                kern_pos_cont{krn}=[pat_x, pat_y];
            end
            
            % Estraiamo il pattern (nella posizione estratta) dall'immagine
            pat = IMG( pat_x : (pat_x+kernel_dim-1) ,  pat_y : (pat_y+kernel_dim-1) );
            
            % Aggiungiamo la crosscorrelazione attuale alla media
            xcorr_full = xcorr_full + 1/kernel_amount .* normxcorr2(pat,IMG);
        end
        
        % Tagliamo la xcorr alla dimensione corretta
        xcorr = xcorr_full(kernel_dim-1:end-kernel_dim+1,kernel_dim-1:end-kernel_dim+1); % size(pattern)-1
        xcorr = abs(xcorr);
        xcorr = imgaussfilt(xcorr,2);
        imagesc(xcorr);
        pause(.5)
        
        % ---- Calcoliamo la treshold ideale con Otsu
        T = graythresh(xcorr(30:end-30, 30:end-30))*.9;
        
        % ---- Generiamo la maschera
        mask_raw = xcorr<T;
        
        % ---- Refining della maschera
        se = strel('disk',disk_dim);
        mask = imopen(mask_raw,se);
        mask = imclose(mask,se);
        mask = bwareaopen(mask, areaopen);
        
        
        %Salviamo la maschera finale (nel tipo corretto)
        if k_a==1
            xcorr_corr = xcorr;
            mask_corr = mask;
            mask_raw_corr = mask_raw;
        else
            xcorr_cont = xcorr;
            mask_cont = mask;
            mask_raw_cont = mask_raw;
        end        
    end
    
    
        figure();
        subplot(231);        imagesc(xcorr_corr);        title("xcorr corr");
        subplot(232);        imshow(mask_raw_corr);        title("mask corr");
        subplot(233);        imshow(mask_corr);        title("mask corr");
        subplot(234);        imagesc(xcorr_cont);        title("xcorr cont");
        subplot(235);        imshow(mask_raw_cont);        title("mask cont");
        subplot(236);        imshow(mask_cont);        title("mask cont");
    
    % ---- Scelta della maschera migliore:
    % Di default prendo CORR.
    % Passo a CONT se:
    %   - CONT ha meno aree
    %   - a parità di aree, cont ha percentuale di selezione maggiore
    % Se nessuna delle due va bene lanciamo GABOR.
    
    [topology_corr, selected_ratio_corr] = is_reliable(mask_corr,IMG);
    [topology_cont, selected_ratio_cont] = is_reliable(mask_cont,IMG);
    fprintf("[Corr: %d, %.1f%%\tCont: %d, %.1f%%]\n",...
        topology_corr, selected_ratio_corr,topology_cont, selected_ratio_cont);
    
    choice = "corr";    
    if selected_ratio_corr <= 0.1 
        choice = "cont";
        fprintf("B) Switching to CONT because CORR mask was empty\n");
    elseif topology_cont < topology_corr
        choice = "cont";
        fprintf("B) Switching to CONT because of bad topology\n");
    elseif topology_cont == topology_corr && selected_ratio_cont > selected_ratio_corr
        choice = "cont";
        fprintf("B) Switching to CONT because of same topology + better selection ratio.\n");
    else
        fprintf("B) CORR map seems optimal.\n");
    end
    
    if choice == "corr"
        xcorr = xcorr_corr;
        kernel_dim = kernel_corr;
        mask_raw = mask_raw_corr;
        mask= mask_corr;
        kernel_type = 'CORR';
        kern_pos = kern_pos_corr;
    else
        xcorr = xcorr_cont;
        kernel_dim = kernel_cont;
        mask_raw = mask_raw_cont;
        mask= mask_cont;
        kernel_type = 'CONT';
        kern_pos = kern_pos_cont;
    end
    
    
    if selected_ratio_cont <= 0.1
        kernel_type = 'GABOR';
        fprintf("B.2) Both masks are empty; switching to GABOR. Potrebbe volerci qualche secondo.. >>\n");
        [mask, mask_raw, xcorr] = gabor_emergency(IMG,filename);
        kernel_dim = 1;
    end
    
    % ---- Ritaglio IMG (solo se NON sto usando Gabor) e applicazione maschera
    if kernel_type ~= "GABOR"
        border = kernel_dim / 2;
        warning('off');IMG=IMG(border:end-border+1,border:end-border+1);warning('on');
    end
    
    % Clippiamo al massimo i valori dell'immagine che corrispondono alla maschera
    IMG_selected = IMG;    IMG_selected(mask)=255;
    
    % Creiamo immagine a tre canali mettendo la versione selezionata sulcanale rosso
    IMG_masked=cat(3,IMG_selected,IMG,IMG);
    
    
    %% --- F I G U R E S
    % Questa sezione genera (e salva) le immagini di risultato, secondo quello
    % che è settato dalle impostazioni.
    
    [~, selected_pixels_ratio] = is_reliable(mask,IMG); % mi tornerà utile :)
    
    if show_resume == true
        
        % --- Figure 1: riassuntazzo
        figure();
        
        %Titolo
        sgtitle(sprintf('Risultato immagine %s (rs)\n%.1f%% selected',...
            filename,selected_pixels_ratio));
        
        % Visualizzazione patterns prelevati
        subplot(231);
        imagesc(IMG_RGB); axis image; colormap gray; hold on;
        if kernel_type == "GABOR"
            title('Immagine originale');
        else
            title('Img originale');
            
            for krn=1:kernel_amount
                position = kern_pos{krn};
                pat_x = position(1);
                pat_y = position(2);
                rectangle('position',[pat_x,pat_y,kernel_dim,kernel_dim],'EdgeColor','r');
            end
            hold off
        end
        
        if show_resume_choice == false
            %Visualizziamo la xcorr risultante
            corr_img = subplot(232);
            imagesc(xcorr); axis image; colormap(corr_img,jet);
            if kernel_type == "GABOR"
                title('Gabor mediato');
            else
                title('Mappa di cross-correlazione');
            end
            
            %Visualizziamo la maschera raw
            subplot(233);
            imagesc(mask_raw); axis image;
            title('Maschera raw');
            
            %Visualizziamo maschera rifinita
            subplot(234);
            imagesc(mask); axis image;
            title('Maschera strel-ata');
            
            %Visualizziamo risultato
            subplot(224);
            imshowpair(IMG,IMG_masked,'montage')
            title(sprintf('Risultato\n[%.2f%% - Kernel: %s,%d]',...
                selected_pixels_ratio,kernel_type,kernel_dim));
            
        else
            % Visualizziamo le due maschere alternative
            subplot(232);
            imagesc(mask_corr); axis image;
            title('Maschera CORR strel-ata');
            subplot(233);
            imagesc(mask_cont); axis image;
            title('Maschera CONT strel-ata');
            
            %Visualizziamo risultato
            subplot(212);
            imshowpair(IMG,IMG_masked,'montage')
            title(sprintf('Scelta: %s',kernel_type));
            
        end
        
        
        % Salvataggio
        resname =sprintf('results\\%s-RS',filename);
        saveas(gcf, resname,'png');
        
        if analyze_just_one == false
            close all;
        end
    end
    
    
    % ---- Figure 2 - risultato
    if show_result == true
        
        f=figure();
        subplot(121);
        imshow(IMG_RGB);
        title('Immagine originale');
        
        subplot(122);
        imshow(IMG_masked);
        title('Maschera');
        
        
        sgtitle(sprintf('Risultato immagine %s RS\n\nT = %.3f\n%.1f%% selected\nTipo di analisi: %s',...
            filename,T,selected_pixels_ratio,kernel_type));
        
        saveas(gcf, sprintf('results\\%s-RS',filename),'png');
        
        if analyze_just_one == false
            close(f);
        end
    end
    
    
end



