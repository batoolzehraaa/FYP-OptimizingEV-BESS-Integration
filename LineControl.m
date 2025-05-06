% Initialize OpenDSS COM interface
clc; clear all;
DSSObj = actxserver('OpenDSSEngine.DSS');
DSSObj.Start(0);  % Start DSS Engine
DSSText = DSSObj.Text;
DSSCircuit = DSSObj.ActiveCircuit;

% Load OpenDSS file and compile
DSSText.Command = 'compile (C:\Users\HP\Desktop\Sem 7\FYP\Sir Files\GridModel-bus13.dss)';  
DSSText.Command = 'solve mode=time stepsize=1s number=1';

% Define the line name you want to control
line_name = '684652';  % Setting line name from the DSS model here

% Initialize Time and Simulation Parameters
simTime = 0;  % Start time
endTime = 15;  % Simulate for 15 seconds 
time_step = 1;  % Step size of 1 second

i = 1;
prev_line_control = NaN;  % Initializing previous line control variable

while simTime <= endTime

    set_param('COSIMscenario2', 'SimulationCommand', 'start');  % Start Simulink model

    % Get the line control signal from Simulink
    line_control = get_param('COSIMscenario2/Line Control Constant', 'Value');  
    line_control = str2double(line_control);  % Convert to numeric type    

    % Displaying voltages and source power only when line status changes
    if line_control ~= prev_line_control
        % Fetch total circuit power before enabling/disabling
        source_power_before = DSSCircuit.TotalPower;  % Fetch real and reactive power before
        kW_before = source_power_before(1);
        kVAR_before = source_power_before(2);
        kVA_before = sqrt(kW_before^2 + kVAR_before^2);  % Calculate kVA before
        
        % Display total circuit (source) power before enabling/disabling
        fprintf('\nSource Power Before:\n');
        fprintf('  Real Power = %.2f kW\n', kW_before);
        fprintf('  Reactive Power = %.2f kVAR\n', kVAR_before);
        fprintf('  Apparent Power = %.2f kVA\n\n', kVA_before);

        % Display phase voltages before enabling/disabling
        %fprintf('Before Line Phase Voltages:\n');
        V1_before(:,i) = DSSCircuit.AllNodeVmagPUByPhase(1)';
        V2_before(:,i) = DSSCircuit.AllNodeVmagPUByPhase(2)';
        V3_before(:,i) = DSSCircuit.AllNodeVmagPUByPhase(3)';

        %fprintf('  Phase 1 Voltage: %s\n', num2str(V1_before(:,i)'));
        %fprintf('  Phase 2 Voltage: %s\n', num2str(V2_before(:,i)'));
        %fprintf('  Phase 3 Voltage: %s\n\n', num2str(V3_before(:,i)'));

        % Control the line
        if line_control == 0
            DSSText.Command = ['edit Line.', line_name, ' enabled=no'];
            fprintf('Action: Line %s Disabled\n\n', line_name);  % Added extra newline here
        else
            DSSText.Command = ['edit Line.', line_name, ' enabled=yes'];
            fprintf('Action: Line %s Enabled\n\n', line_name);  % Added extra newline here
        end

        DSSText.Command = 'solve';

        % Display voltages and source power after enabling/disabling
        %fprintf('After Line Phase Voltages:\n');
        V1_after(:,i) = DSSCircuit.AllNodeVmagPUByPhase(1)';
        V2_after(:,i) = DSSCircuit.AllNodeVmagPUByPhase(2)';
        V3_after(:,i) = DSSCircuit.AllNodeVmagPUByPhase(3)';

        %fprintf('  Phase 1 Voltage: %s\n', num2str(V1_after(:,i)'));
        %fprintf('  Phase 2 Voltage: %s\n', num2str(V2_after(:,i)'));
        %fprintf('  Phase 3 Voltage: %s\n\n', num2str(V3_after(:,i)'));

        % Fetch and display total circuit power after enabling/disabling
        source_power_after = DSSCircuit.TotalPower;
        kW_after = source_power_after(1);
        kVAR_after = source_power_after(2);
        kVA_after = sqrt(kW_after^2 + kVAR_after^2);  % Calculate kVA after

        fprintf('Source Power After:\n');
        fprintf('  Real Power = %.2f kW\n', kW_after);
        fprintf('  Reactive Power = %.2f kVAR\n', kVAR_after);
        fprintf('  Apparent Power = %.2f kVA\n\n', kVA_after);

        % Update the previous line control value
        prev_line_control = line_control;
    end

    % Update the voltages in Simulink
    set_param('COSIMscenario2/Network Voltages Phase-A ', 'Value', ['[',num2str(V1_after(:,end)'),']']);
    set_param('COSIMscenario2/Network Voltages Phase-B', 'Value', ['[',num2str(V2_after(:,end)'),']']);
    set_param('COSIMscenario2/Network Voltages Phase-C', 'Value', ['[',num2str(V3_after(:,end)'),']']);
    
    % Step Simulink for 1 second
    set_param('COSIMscenario2','SimulationCommand','step');

    % Increment simulation time
    simTime = simTime + time_step;  % Move to the next time step
    i = i + 1;
end

% Stop Simulink simulation
set_param('COSIMscenario2','SimulationCommand','stop');