% Initialize OpenDSS COM interface  
clc; clear all;
DSSObj = actxserver('OpenDSSEngine.DSS');
DSSObj.Start(0);  % Start DSS Engine
DSSText = DSSObj.Text;
DSSCircuit = DSSObj.ActiveCircuit;

% Load OpenDSS file and compile
DSSText.Command = 'compile (C:\Users\HP\Desktop\Sem 7\FYP\Sir Files\GridModel-bus13.dss)';  

% Define Fault Parameters
fault_bus = '675.1';  % Specify the bus where you want to apply the fault
fault_phase = 1;          % Specify the phase for the fault (1, 2, or 3)
fault_resistance_active = 0.002;  % Low resistance for fault state
fault_resistance_inactive = 1e5;   % High resistance to effectively clear the fault

% Set the initial State of Charge and Capacity
DSSText.Command = '? Storage.BESS1.%stored';
SOC_init = DSSText.Result;
DSSText.Command = '? Storage.BESS1.KWhrated';
Capacity = DSSText.Result;

% Initialize parameters in Simulink using set_param
set_param('COSIMscenario3/Capacity', 'Value', num2str(Capacity));
set_param('COSIMscenario3/SOC_prev', 'Value', num2str(SOC_init));
SOC_value = str2num(SOC_init);

% Initialize fault element in OpenDSS (create once at the beginning)
DSSText.Command = sprintf('New Fault.F1 phase=%d bus1=%s R=%.4f temporary=yes', fault_phase, fault_bus, fault_resistance_inactive);

% Simulation parameters
simTime = 0;  % Start time
endTime = 15;  % Simulate for 20 seconds
time_step = 1;  % Step size of 1 second

SOC_over_time = [];  % To store SOC values over time
time_vector = [];    % To store time values

% Start Simulink simulation
set_param('COSIMscenario3', 'SimulationCommand', 'start');
set_param('COSIMscenario3', 'SimulationCommand', 'pause');

fault_active = false;  % Flag to track if the fault is active

i = 1;
while simTime <= endTime
    % Read the Fault Trigger signal from Simulink
    fault_trigger_rto = get_param('COSIMscenario3/Fault Trigger', 'RuntimeObject');
    fault_trigger = fault_trigger_rto.OutputPort(1).Data;

    % Apply or clear the fault based on the Fault Trigger signal
    if fault_trigger > 0 && ~fault_active
        % Activate the fault by setting a low resistance
        DSSText.Command = sprintf('Edit Fault.F1 R=%.4f', fault_resistance_active);
        disp('Fault applied in OpenDSS');
        fault_active = true;
    elseif fault_trigger == 0 && fault_active
        % Clear the fault by setting a high resistance
        DSSText.Command = sprintf('Edit Fault.F1 R=%.4f', fault_resistance_inactive);
        disp('Fault cleared in OpenDSS');
        fault_active = false;
    end

    % Retrieve current P_BESS from Simulink
    rto = get_param('COSIMscenario3/Memory', 'RuntimeObject');
    P_BESS = rto.OutputPort(1).Data;

    % Update P_BESS in OpenDSS
    if P_BESS >= 0
        DSSText.Command = ['Storage.BESS1.kW=', num2str(P_BESS)];
        DSSText.Command = 'Storage.BESS1.State=discharging';
    else
        DSSText.Command = ['Storage.BESS1.kW=', num2str(-P_BESS)];
        DSSText.Command = 'Storage.BESS1.State=charging';
    end

    % Solve the circuit with updated parameters
    DSSText.Command = 'solve number=1';

    % Get SOC Value from OpenDSS
    DSSText.Command = '? Storage.BESS1.%stored';
    SOC_val(i) = str2num(DSSText.Result);
    set_param('COSIMscenario3/SOC_prev', 'Value', DSSText.Result);

    % Retrieving network voltages from OpenDSS
    V1(:,i) = DSSCircuit.AllNodeVmagPUByPhase(1)';
    V2(:,i) = DSSCircuit.AllNodeVmagPUByPhase(2)';
    V3(:,i) = DSSCircuit.AllNodeVmagPUByPhase(3)';

    % Updating network voltages in Simulink
    set_param('COSIMscenario3/Network Voltages Phase-A ', 'Value', ['[', num2str(V1(:,end)'), ']']);
    set_param('COSIMscenario3/Network Voltages Phase-B', 'Value', ['[', num2str(V2(:,end)'), ']']);
    set_param('COSIMscenario3/Network Voltages Phase-C', 'Value', ['[', num2str(V3(:,end)'), ']']);

    % Run Simulink for 1 second
    set_param('COSIMscenario3', 'SimulationCommand', 'step');

    % Store SOC over time for plotting
    SOC_over_time = [SOC_over_time; SOC_value];
    time_vector = [time_vector; simTime];

    % Print debug information
    fprintf('Time: %.2f sec, P_BESS: %.2f kW, SOC: %.2f%%\n', simTime, P_BESS, SOC_value);

    % Increment time
    simTime = simTime + time_step;
    i = i + 1;
end
% Stop the Simulink simulation
set_param('COSIMscenario3', 'SimulationCommand', 'stop');
