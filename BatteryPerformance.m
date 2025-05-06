% Initialize OpenDSS COM interface
clc; clear all;
% load("matlab.mat");
DSSObj = actxserver('OpenDSSEngine.DSS');
DSSObj.Start(0);  % Start DSS Engine
DSSText = DSSObj.Text;
DSSCircuit = DSSObj.ActiveCircuit;

% Loading OpenDSS file and compile
DSSText.Command = 'compile (C:\Users\HP\Desktop\Sem 7\FYP\Sir Files\GridModel-bus13.dss)';  % Adjust the path to your DSS file

% Solve the circuit to initialize
DSSText.Command = 'solve mode=time stepsize=1s number=1';

% Retrieve the initial SOC and Capacity
DSSText.Command='? Storage.BESS1.%stored';
SOC_init = str2num(DSSText.Result);  % Convert result to numerical value
DSSText.Command='? Storage.BESS1.KWhrated';
Capacity = str2num(DSSText.Result);  % Capacity in kWh

% Initial Parameters in Simulink Using set_param
set_param('COSIM/Capacity', 'Value', num2str(Capacity));  % Set the Capacity in Simulink
set_param('COSIM/SOC_prev', 'Value', num2str(SOC_init));  % Set the initial SOC in Simulink
SOC_value = SOC_init;

% Initializing Time and Simulation Parameters
simTime = 0;  % Start time
endTime = 15;  % Simulate for 15 seconds
time_step = 1;  % Step size of 1 second

% Retrieve number of nodes in each phase
numNodesPhase1 = length(DSSCircuit.AllNodeVmagPUByPhase(1));
numNodesPhase2 = length(DSSCircuit.AllNodeVmagPUByPhase(2));
numNodesPhase3 = length(DSSCircuit.AllNodeVmagPUByPhase(3));

% Preallocate matrices for voltage values based on number of nodes in each phase
V1 = zeros(numNodesPhase1, endTime);  % Preallocate for phase A
V2 = zeros(numNodesPhase2, endTime);  % Preallocate for phase B
V3 = zeros(numNodesPhase3, endTime);  % Preallocate for phase C

SOC_over_time = [];  % To store SOC values over time
time_vector = [];  % To store time values
DSSText.Command = '? Storage.BESS1.kW';
P_BESS = str2num(DSSText.Result);  % Initial power value

% Step 8: Initialize the simulation
set_param('COSIM','SimulationCommand','start');
set_param('COSIM','SimulationCommand','pause');

% Main simulation loop
i = 1;
while simTime <= endTime
    % Retrieve current P_BESS from OpenDSS
    rto = get_param('COSIM/Memory', 'RunTimeObject');
    P_BESS = rto.OutputPort(1).Data;
    
    % Add AWGN noise to P_BESS
    noise = 0.1 * randn();  % Gaussian noise with standard deviation of 10% of P_BESS
    P_BESS_noisy = P_BESS + noise;  % Apply noise to the power value

    % Update the P_BESS value in OpenDSS using DSSText.Command
    if P_BESS_noisy >= 0
        DSSText.Command = ['Storage.BESS1.kW=', num2str(P_BESS_noisy)];  % Update kW with noisy P_BESS
        DSSText.Command = ['Storage.BESS1.State=discharging'];
    else
        DSSText.Command = ['Storage.BESS1.kW=', num2str(-P_BESS_noisy)];  % Update kW with noisy P_BESS
        DSSText.Command = ['Storage.BESS1.State=charging'];
    end

    % Solve the circuit to update OpenDSS with the new power value
    DSSText.Command = 'solve number=1';

    % Get SOC Value from OpenDSS
    DSSText.Command = '? Storage.BESS1.%stored';
    SOC_val(i) = str2num(DSSText.Result);
    set_param('COSIM/SOC_prev', 'Value', DSSText.Result);

    % Voltages from OpenDSS (for further processing, if needed)
    V1(:, i) = DSSCircuit.AllNodeVmagPUByPhase(1);  % Match dimensions of the retrieved voltages
    V2(:, i) = DSSCircuit.AllNodeVmagPUByPhase(2);  % Match dimensions of the retrieved voltages
    V3(:, i) = DSSCircuit.AllNodeVmagPUByPhase(3);  % Match dimensions of the retrieved voltages

    % Pause Simulink to safely update parameters
    set_param('COSIM', 'SimulationCommand', 'pause');
    
    % Update Simulink with the new voltage values
    set_param('COSIM/Network Voltages Phase-A', 'Value', ['[', num2str(V1(:, i)'), ']']);
    set_param('COSIM/Network Voltages Phase-B', 'Value', ['[', num2str(V2(:, i)'), ']']);
    set_param('COSIM/Network Voltages Phase-C', 'Value', ['[', num2str(V3(:, i)'), ']']);
    
    % Resume Simulink after updating parameters
    set_param('COSIM', 'SimulationCommand', 'continue');

    % Store SOC over time
    SOC_over_time = [SOC_over_time; SOC_val(i)];
    time_vector = [time_vector; simTime];

    % Print SOC for debugging
    fprintf('Time: %.2f sec, P_BESS: %.2f kW (with noise: %.2f), SOC: %.2f%%\n', simTime, P_BESS, P_BESS_noisy, SOC_val(i));

    % Increment simulation time
    simTime = simTime + time_step;
    i = i + 1;
end

% Plotting the SOC over time
figure;
plot(time_vector, SOC_over_time, 'LineWidth', 1.5);
xlabel('Time (s)');
ylabel('State of Charge (%)');
title('SOC over Time with AWGN Noise');
grid on;

% Stop the Simulink simulation
set_param('COSIM', 'SimulationCommand', 'stop');