clc;
clear all;
% Initialize OpenDSS
DSSObj = actxserver('OpenDSSEngine.DSS');
DSSObj.Start(0);  % Start DSS Engine
DSSText = DSSObj.Text;
DSSCircuit = DSSObj.ActiveCircuit;

% Compile the OpenDSS script
DSSText.Command = 'compile (C:\\Users\\HP\\Desktop\\Sem 7\\FYP\\Invconnection\\Grid.dss)';
DSSText.Command = 'solve Mode=time stepsize=1s maxcontroliter=1000'; % OpenDSS timestep: 1 second
DSSText.Command = 'Set Number=1';

% Simulation time parameters
simTime = 0;                % Start time
endTime = 2;                % End time
openDSSTimeStep = 1;        % OpenDSS time step (1 second)

mdl = 'Grid_connected_converter_updated'; % Simulink model name
open(mdl);
set_param(mdl, 'SaveFinalState', 'on', 'FinalStateName', [mdl 'SimState'], 'SaveCompleteFinalSimState', 'on');
set_param(mdl, 'LoadInitialState', 'off');
DSSText.Command = '? Storage.BESS1.%stored';
SOC_init = str2double(DSSText.Result);
DSSText.Command = '? Storage.BESS1.KWhrated';
Capacity = str2double(DSSText.Result);
DSSText.Command = '? Storage.BESS1.kW';
P_BESS_rated = str2double(DSSText.Result);

% Define transformer and bus for tap change
transformerName = 'Transformer.Sub';  
tapPositionCommand = ['? ' transformerName '.Tap'];  
DSSText.Command = tapPositionCommand;
currentTapPosition = str2double(DSSText.Result);  % Current tap position
vprimaryprev=[];
powerprev=[]
% Main simulation loop
while simTime < endTime
    if simTime == 1 
        newTapPosition = currentTapPosition + 0.05; % Example logic to increment tap position
        DSSText.Command = ['edit ' transformerName ' Tap=' num2str(newTapPosition)];
        disp(['Updated transformer tap to: ', num2str(newTapPosition)]);
        
        DSSText.Command = 'solve';
    end

    DSSCircuit.SetActiveBus('671.1.2.3');  
    Busespu = DSSCircuit.ActiveBus.PuVoltages;

    Bus_phase1 = abs(Busespu(1) + 1i * Busespu(2));  % Phase 1 voltage (per-unit)
    Bus_phase2 = abs(Busespu(3) + 1i * Busespu(4));  % Phase 2 voltage (per-unit)
    Bus_phase3 = abs(Busespu(5) + 1i * Busespu(6));  % Phase 3 voltage (per-unit)

    disp(['Updated Voltage Phase 1 (OpenDSS): ', num2str(Bus_phase1), ' p.u.']);
    disp(['Updated Voltage Phase 2 (OpenDSS): ', num2str(Bus_phase2), ' p.u.']);
    disp(['Updated Voltage Phase 3 (OpenDSS): ', num2str(Bus_phase3), ' p.u.']);

    set_param([mdl '/Voltage_controlled_source/Va'], 'Value', num2str(Bus_phase1));
    set_param([mdl '/Voltage_controlled_source/Vb'], 'Value', num2str(Bus_phase2));
    set_param([mdl '/Voltage_controlled_source/Vc'], 'Value', num2str(Bus_phase3));

    % Simulate for the next time step
    simOut = sim(mdl, 'StartTime', num2str(simTime), 'StopTime', num2str(simTime + openDSSTimeStep - eps), ...
        'SaveFinalState', 'on', 'FinalStateName', 'SimState');
    SimState = simOut.get('SimState');
    set_param(mdl, 'LoadInitialState', 'on', 'InitialState', 'SimState');
    Combinedpower=simOut.power;
    Combinedpower=[powerprev;Combinedpower];
    Vprimary=simOut.Vprimary;
    Vprimary=[vprimaryprev;Vprimary];
    simTime = simTime + openDSSTimeStep;
    vprimaryprev=simOut.Vprimary;
    powerprev=simOut.power;
    
end

% Stop the simulation
set_param(mdl, 'SimulationCommand', 'stop');
set_param(mdl, 'LoadInitialState', 'off');
