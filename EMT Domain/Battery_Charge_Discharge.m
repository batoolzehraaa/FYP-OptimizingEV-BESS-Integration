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
vprimaryprev=[];
powerprev=[]
% Main simulation loop
while simTime < endTime
    if simTime == 1
        % Extract the power from load connected to bus 671.1.2.3
        DSSCircuit.SetActiveBus('671.1.2.3');  % Set the active bus
        DSSText.Command = '? Load.671.kW';
        loadActivePower = str2double(DSSText.Result);
        DSSText.Command = '? Load.671.kvar';% Active power (kW)
        loadReactivePower = str2double(DSSText.Result);  % Reactive power (kVAR)

        P_allocated = -20e3;  % kW 
        Q_allocated = -20e3;  % kVAR 

        set_param([mdl '/Active power'], 'Value', num2str(P_allocated));
        set_param([mdl '/Reactive Power'], 'Value', num2str(Q_allocated));

        % Update remaining power in DSS
        P_remaining = loadActivePower - P_allocated;  % Remaining real power
        Q_remaining = loadReactivePower - Q_allocated;  % Remaining reactive power

        % Update the remaining power back to OpenDSS
        DSSText.Command = ['edit Load.671 kW=' num2str(P_remaining)];
        DSSText.Command = ['edit Load.671 kVAR=' num2str(Q_remaining)];

        % Solve DSS after power update
        DSSText.Command = 'solve';
    end

    Busespu = DSSCircuit.ActiveBus.PuVoltages;

    % Convert per-unit voltages to  for each phase
    Bus_phase1 = abs(Busespu(1) + 1i * Busespu(2));  % Phase 1 voltage (per-unit)
    Bus_phase2 = abs(Busespu(3) + 1i * Busespu(4));  % Phase 2 voltage (per-unit)
    Bus_phase3 = abs(Busespu(5) + 1i * Busespu(6));  % Phase 3 voltage (per-unit)

    % Update Simulink model with the new voltages
    set_param([mdl '/Voltage_controlled_source/Va'], 'Value', num2str(Bus_phase1));
    set_param([mdl '/Voltage_controlled_source/Vb'], 'Value', num2str(Bus_phase2));
    set_param([mdl '/Voltage_controlled_source/Vc'], 'Value', num2str(Bus_phase3));

    % Simulating for one timestep
    simOut = sim(mdl, 'StartTime', num2str(simTime), 'StopTime', num2str(simTime + openDSSTimeStep - eps), ...
        'SaveFinalState', 'on', 'FinalStateName', 'SimState');
    
    % Get the simulation state and load it in the next iteration
    SimState = simOut.get('SimState');
    set_param(mdl, 'LoadInitialState', 'on', 'InitialState', 'SimState');
    Combinedpower_temp=simOut.power;
    Combinedpower=[powerprev;Combinedpower_temp];
    Vprimary_temp=simOut.Vprimary;
    Vprimary=[vprimaryprev;Vprimary_temp];
    % Update simulation time
    simTime = simTime + openDSSTimeStep;
    vprimaryprev=Vprimary;
    powerprev=Combinedpower;
end

% Stop the simulation
set_param(mdl, 'SimulationCommand', 'stop');
set_param(mdl, 'LoadInitialState','off');
