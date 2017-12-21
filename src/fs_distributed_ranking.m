function [ FRankings, IRankings, FRankings_README, IRankings_README, timesPerFilter ] = ...
    fs_distributed_ranking( ShowMessage, MXTrain, MYTrain, indices, RankerMethods, ...
                         UnionMethods, ThresholdValues )
%FS_ENSEMBLE_RANKING Summary of this function goes here
%   Detailed explanation goes here
%
%   INPUTS:
%   -----------------------------------------------------------------------
%   ShowMessage ----------> Variable que indica si se muestran mensajes de
%   progreso por pantalla o no. Acepta dos valores:
%       - logical(0) o false -> no muestra mensajes por pantalla.
%       - logical(1) o true -> muestra mensajes por pantalla.
%   MXTrain --------------> Matriz que representa el dataset sobre el que
%   se desea realizar la selecci�n de caracter�sticas. La matriz tendr�
%   tantas filas como n�mero de muestras existen en el dataset, y cada
%   columna representar� una caracter�stica concreta. Por lo tanto, matriz
%   de tama�o [num_muestras x num_caracteristicas].
%   MYTrain --------------> Matriz que representa las clases en las que se
%   clasifica cada una de las muestras del dataset. La matriz tendr� tantas
%   filas como muestras existen en el dataset, y una �nica columna que
%   indica la clase a la que est� asociada la muestra. Por lo tanto, matriz
%   de tama�o [num_muestras x 1]
%   RankerMethods --------> Array que contiene los n�meros de los m�todos
%   de selecci�n de caracter�sticas que se utilizan para formar el ensemble
%   final. Los m�todos aceptados van de 1 a MAX_FS_METHODS y se
%   corresponden con los siguientes respectivamente:
%       1 - ChiSquare
%       2 - InfoGain
%       3 - mRMR
%       4 - ReliefF
%       5 - SVM_RFE
%       6 - FSP
%   Por defecto, el ensemble est� formado por todos los m�todos
%   anteriormente numerados.
%   UnionMethods ---------> Array que contiene los n�meros de los m�todos
%   de uni�n de rankings que se utilizan para obtener el ranking final. Los
%   m�todos aceptados van de 1 a MAX_UNION_METHODS y se
%   corresponden con los siguientes respectivamente:
%       1 - SVM-Rank (valor por defecto)
%       2 - Min
%       3 - Median
%       4 - Mean
%       5 - GeomMean
%       6 - Stuart
%       7 - RRA
%   ThresholdValues ------> Array que contiene los n�meros de los valores
%   de umbral que se utilizan para obtener el ranking final. Los umbrales
%   aceptados van de 1 a MAX_THRESHOLD_VALUES y se corresponden con los
%   siguientes respectivamente:
%       1 - Fisher discrimination ratio
%       2 - log2(n) value
%       3 - 10%
%       4 - 25%
%       5 - 50%
%       6 - 100% (valor por defecto)
%
%   EJEMPLO DE LLAMADA A LA FUNCION:
%       1 - Cargar un dataset de la carpeta data_test.
%       2 - Realizar la llamada a la funcion:
%           [F I] = fs_ensemble_ranking(true, dataset, classes, ...
%                                       [1,2,3,4,5,6], [1,2,3,4,5,6,7], ...
%                                       [1,2,3,4,5,6])
%
%   OUTPUTS:
%   -----------------------------------------------------------------------
%   FRankings ------------> Matriz de celdas que representa los rankings de
%   caracteristicas finales. La matriz tendr� tantas filas como n�mero de 
%   metodos de union se han indicado por parametro de entrada, y tantas
%   columnas como valores de umbral se han seleccionado. Cada elemento
%   celda de la matriz hace referencia a un ranking obtenido por una
%   configuracion "metodo de union - valor de umbral" concreta. Las filas y
%   columnas siguen el mismo orden que se indic� en los par�metros de
%   entrada. Por ejemplo, si se indica UnionMethods = [1,3,5] y 
%   ThresholdValues = [2,6], la matriz resultado ser� de la forma:
%   
%                           ThresholdValue [2]     ThresholdValue [6]
%       UnionMethod [1] ->     [Ranking 1,2]          [Ranking 1,6]
%       UnionMethod [3] ->     [Ranking 3,2]          [Ranking 3,6]
%       UnionMethod [5] ->     [Ranking 5,2]          [Ranking 5,6]
%   
%   Por lo tanto, la matriz de celdas resultado ser� de tama�o 
%   [num_metodos_union x num_valores_umbral].
%   IRankings ------------> Matriz de celdas que representa los rankings de
%   caracteristicas parciales, obtenidos para cada metodo de seleccion de
%   caracteristicas individual. La matriz tendr� una columna por cada valor
%   de umbral indicado como parametro, y tantas filas como n�mero de 
%   metodos de seleccion se han indicado tambien por parametro de entrada.
%   Cada elemento celda de la matriz hace referencia a un ranking obtenido.
%   Las filas siguen el mismo orden que se indic� en el par�metro de
%   entrada "RankerMethods" y las columnas el del parametro 
%   "ThresholdValues". Por ejemplo, si se indica RankerMethods = [1,3,5] y
%   ThresholdValues = [2,6] la matriz de resultados parciales ser� de la
%   forma:
%   
%                           ThresholdValue [2]     ThresholdValue [6]
%       RankerMethod [1] ->    [Ranking 1,2]         [Ranking 1,6]
%       RankerMethod [3] ->    [Ranking 3,2]         [Ranking 3,6]
%       RankerMethod [5] ->    [Ranking 5,2]         [Ranking 5,6]
%   
%   Por lo tanto, la matriz de celdas resultado ser� de tama�o 
%   [num_metodos_ranker x num_valores_umbral].


%% MAX STATIC VALUES
MAX_FS_METHODS = 6;
MAX_UNION_METHODS = 7;
MAX_THRESHOLD_VALUES = 10;

UNION_METHODS_LIST = {'svmrank','min','median','mean','geomMean','stuart','RRA'};
cParam = 3; % Numero de parametros del SVM-Rank.

%% LOAD INITIAL PATH
[wekaPath rootDir] = load_path;

%% DEFAULT VALUES
RankerMethodsDefault = [1,2,3,4,5,6];
UnionMethodsDefault = [1];
ThresholdValuesDefault = [6];
nodes = 4;

%% PRE-PROCESS

if (nargin >=4)
    if (~islogical(ShowMessage))
        error('ERROR: El par�metro "ShowMessage" solo acepta los valores "false" (logical(0)) o "true" (logical(1))');
    end
    % nsamples: Numero de muestras del conjunto.
    % nfeats: Numero de caracteristicas de cada muestra.
    [nsamples1, nfeats] = size(MXTrain);
    [nsamples2, nclasses] = size(MYTrain);
    if (nsamples1 ~= nsamples2)
        error('ERROR: Numero de filas no coincidente entre las matrices de datos de entrada');
    end
    if (nclasses ~= 1)
        error('ERROR: N�mero de columnas en la matriz de entrada de clases diferente de 1');
    end
else error('ERROR: N�mero de argumentos incorrecto. Al menos debe incluir una matriz de datos y una matriz de clases');
end

switch(nargin)
    case 4,
        if (ShowMessage)
            sprintf('Se utilizan los valores por defecto para "RankerMethods", "UnionMethods" y "ThresholdValues"')
        end
        RankerMethods = RankerMethodsDefault;
        UnionMethods = UnionMethodsDefault;
        ThresholdValues = ThresholdValuesDefault;
    case 5,
        if (ShowMessage)
            sprintf('Se utilizan los valores por defecto para "UnionMethods" y "ThresholdValues"')
        end
        UnionMethods = UnionMethodsDefault;
        ThresholdValues = ThresholdValuesDefault;
    case 6,
        if (ShowMessage)
            sprintf('Se utiliza el valor por defecto para "ThresholdValues"')
        end
        ThresholdValues = ThresholdValuesDefault;
    case 7,
    otherwise 
        error('ERROR: N�mero de argumentos incorrecto.');
end

% Se comprueba que los parametros pasados como entrada de la funcion cumplen
% con las caracteristicas especificadas en la documentacion.
if ( min(RankerMethods)<1 | max(RankerMethods)>MAX_FS_METHODS )
    error('ERROR: Valor de "RankerMethods" incorrecto. Revise cuales son los valores aceptados.');
else nRankerMethods = length(RankerMethods);
end
if ( min(UnionMethods)<1 | max(UnionMethods)>MAX_UNION_METHODS )
    error('ERROR: Valor de "UnionMethods" incorrecto. Revise cuales son los valores aceptados.');
else nUnionMethods = length(UnionMethods);
end
if ( min(ThresholdValues)<1 | max(ThresholdValues)>MAX_THRESHOLD_VALUES )
    error('ERROR: Valor de "ThresholdValues" incorrecto. Revise cuales son los valores aceptados.');
else nThresholdValues = max(length(ThresholdValues),1);
end
IRankingsAux = cell(nRankerMethods, nodes);
IRankings = cell(nRankerMethods, nThresholdValues);
IRankings_README = cell(nRankerMethods, nThresholdValues);
auxFeatsRanking = cell(nUnionMethods, 1);
FRankings = cell(nRankerMethods, nUnionMethods, nThresholdValues);
FRankings_README = cell(nUnionMethods, nThresholdValues);
 
%% PROCESS

    % Normalizaci�n de los datos
    minVector = min(MXTrain);
    minVector = repmat(minVector,size(MXTrain,1),1);
    maxVector = max(MXTrain);
    maxVector = repmat(maxVector,size(MXTrain,1),1);
    MXTrain = (MXTrain-minVector)./(maxVector-minVector);
    
    FisherTrainValue = fmulc([MXTrain MYTrain], num2cell(unique(MYTrain))');
    OverlapTrainValue = f2_mul([MXTrain MYTrain], num2cell(unique(MYTrain))');
    EfficiencyTrainValue = f3_mul([MXTrain MYTrain], num2cell(unique(MYTrain))');

    % Se graba a disco el conjunto para su utilizacion en Weka.
    % Weka necesita la entrada de un fichero .arff al ser invocado por
    % linea de comandos.
    fileNameTrain = [rootDir filesep 'train.arff'];
    mat2arff(rootDir, fileNameTrain, [MXTrain MYTrain], wekaPath);
    if (ShowMessage)
        sprintf('Almacenado fichero auxiliar correctamente.')
    end
    
    if (ShowMessage)
        sprintf('Iniciando el proceso de seleccion de caracteristicas...')
    end
    
    
    for n=1:nodes
        XTrainNode = MXTrain(indices==n,:);
        YTrainNode = MYTrain(indices==n);
    
        % Se calculan los diferentes rankings para cada uno de los metodos de
        % seleccion de caracteristicas seleccionados.
        for f=1:nRankerMethods
            tstartfilter = cputime;
            [IRankingsAux{f,n}, namefilter] = ...
                        fs_method(RankerMethods(f), fileNameTrain, XTrainNode, ...
                                  YTrainNode, wekaPath, length(unique(YTrainNode)), ...
                                  nfeats);
            timesPerFilter(f,n) = cputime - tstartfilter;
            IRankings_aux{f,1} = namefilter;
            if (ShowMessage)
                sprintf('Ranking %s calculado correctamente', namefilter)
            end
        end
    end
    % Se borra el fichero auxiliar.
    delete(fileNameTrain);
    
    % Se unen y acotan los rankings de acuerdo a los parametros pasados
    % como entrada de la funcion.
    for f=1:nRankerMethods
        % Se generan los diferentes rankings dependiendo de los
        % metodos de union utilizados.
        for u=1:nUnionMethods;
            % Se construye el ranking conjunto uniendo los resultados de todos
            % los metodos de seleccion.
            sprintf('Vamos a calcular los rankings finales con metodos de union...')
            if UnionMethods(u) == 1
                auxFeatsRanking{u} = svm_rank(IRankingsAux(f,:)', rootDir, cParam);
            else
                complete = 1;
                N = [];
                [aggr pval nom] = aggregateRanks(IRankingsAux(f,:), N, ...
                                        UNION_METHODS_LIST{UnionMethods(u)}, ...
                                        complete, {});
                auxSort = sortrows([aggr nom]);
                auxFeatsRanking{u} = auxSort(:,2);
            end
            sprintf(UNION_METHODS_LIST{UnionMethods(u)})
            featuresNumberFinalRank = size(auxFeatsRanking{u},1);
            sprintf('Vamos a calcular los umbrales...')
            for t=1:nThresholdValues
                % Obtiene el numero de caracteristicas segun el
                % threshold seleccionado
                [numAttrib nomThreshold ~] = ...
                    threshold_value(ThresholdValues(t), featuresNumberFinalRank, ...
                                    auxFeatsRanking{u}, FisherTrainValue, ...
                                    OverlapTrainValue, EfficiencyTrainValue);
                sprintf(nomThreshold)
                FRankings{f,u,t} = (auxFeatsRanking{u}(1:numAttrib))';
                FRankings_README{f,u,t} = [UNION_METHODS_LIST{UnionMethods(u)} ...
                                        ' x ' nomThreshold];
            end
        end
    end
end

