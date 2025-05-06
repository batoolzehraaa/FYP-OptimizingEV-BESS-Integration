% Initialize OpenDSS COM interface
clc; clear all;
DSSObj = actxserver('OpenDSSEngine.DSS');
DSSObj.Start(0);  % Start DSS Engine
DSSText = DSSObj.Text;
DSSCircuit = DSSObj.ActiveCircuit;

% Load and compile the OpenDSS file
DSSText.Command = 'compile (C:\\Users\\HP\\Desktop\\Sem 7\\FYP\\scenarios\\GridModel-bus13.dss)';
DSSText.Command = 'solve Mode=time stepsize=1h maxcontroliter=1000';
DSSText.Command = 'Set Number=1'; % Simulate for 24 hours

% Retrieve initial parameters
DSSText.Command = '? Storage.BESS1.%stored';
SOC_init = str2double(DSSText.Result);
DSSText.Command = '? Storage.BESS1.KWhrated';
Capacity = str2double(DSSText.Result);
DSSText.Command = '? Storage.BESS1.kW';
P_BESS_rated = str2double(DSSText.Result);

% Display initial parameters
disp(['Initial SOC: ', num2str(SOC_init), '%']);
disp(['Capacity: ', num2str(Capacity), ' kWh']);
disp(['Rated Power: ', num2str(P_BESS_rated), ' kW']);

% Set initial parameters in Simulink
set_param('COSIMsim/Capacity', 'Value', num2str(Capacity));  % Set Capacity
set_param('COSIMsim/SOC_prev', 'Value', num2str(SOC_init));  % Set initial SOC
set_param('COSIMsim/P_BESS', 'Value', num2str(P_BESS_rated)); % Set initial power

% Initialize simulation parameters
simTime = 0;  % Start time
endTime = 86400;  % Simulate for 1 day (24 hours)
time_step = 3600;  % Time step in seconds (1 hour)

% Define load profiles for summer and winter
summerLoadProfile = [0.4, 0.5, 0.6, 0.7, 0.8, 1.0, 1.3, 1.5, 1.7, 2.0, 2.2, 2.5, ...
                     2.7, 2.8, 3.0, 3.2, 3.3, 3.3, 3.2, 2.8, 2.5, 2.2, 1.8, 1.5]; 

winterLoadProfile = [0.4, 0.5, 0.7, 0.9, 1.1, 1.4, 1.7, 2.0, 2.2, 2.3, 2.4, 2.5, ...
                     2.5, 2.4, 2.3, 2.2, 2.0, 1.8, 1.7, 1.5, 1.3, 1.1, 0.9, 0.8];

% Define the current month
current_month = 'May'; 

% Choose load profile based on the current month
if ismember(current_month, {'April', 'May', 'June', 'July', 'August', 'September', 'October'})
    loadProfile = summerLoadProfile;  % Use summer load profile
else
    loadProfile = winterLoadProfile;  % Use winter load profile
end

% Defining peak hours based on the month
if ismember(current_month, {'April', 'May', 'June', 'July', 'August', 'September', 'October'})
    peak_start = 18.5;  % 6:30 PM
    peak_end = 22.5;    % 10:30 PM
else
    peak_start = 18;    % 6:00 PM
    peak_end = 22;      % 10:00 PM
end

% Start and pause Simulink simulation
set_param('COSIMsim', 'SimulationCommand', 'start');
set_param('COSIMsim', 'SimulationCommand', 'pause');
SOC_value = SOC_init;

grid_energy_consumed = 0;  % Total energy consumed from grid (kWh)
total_charging_energy = 0;  % Total charging energy (kWh)
total_discharging_energy = 0;  % Total discharging energy (kWh)
total_grid_power = 0;  % Total grid power used (kW)

load_names = {'Load.671', 'Load.634a', 'Load.634b', 'Load.634c', 'Load.645', 'Load.646', 'Load.692', ...
              'Load.675a', 'Load.675b', 'Load.675c', 'Load.611', 'Load.652', 'Load.670a', 'Load.670b', 'Load.670c'};

load_kW = zeros(1, length(load_names));
load_kVAR = zeros(1, length(load_names));

% Main simulation loop
while simTime < endTime
    current_hour = mod(simTime / 3600, 24);  % Current hour (0-23)
    is_peak = (current_hour >= peak_start && current_hour <= peak_end);  % Check if current hour is peak hour

    % Dynamically retrieve SOC from OpenDSS
    DSSText.Command = '? Storage.BESS1.%stored';
    SOC_value = str2double(DSSText.Result);
    SOC_value = max(0, min(100, SOC_value));  % Constrain SOC between 0% and 100%
    V1 = DSSCircuit.AllNodeVmagPUByPhase(1)'; % Phase A
    V2 = DSSCircuit.AllNodeVmagPUByPhase(2)'; % Phase B
    V3 = DSSCircuit.AllNodeVmagPUByPhase(3)'; % Phase C

    load_scaling_factor = loadProfile(mod(simTime / 3600, 24) + 1);  % Scale by load profile
    for i = 1:length(load_names)
        DSSText.Command = ['? ', load_names{i}, '.kW'];
        load_kW(i) = str2double(DSSText.Result);

        DSSText.Command = ['? ', load_names{i}, '.kvar'];
        load_kVAR(i) = str2double(DSSText.Result);

        % Apply load factor to scale the values
        load_kW(i) = load_kW(i) * load_scaling_factor;
        load_kVAR(i) = load_kVAR(i) * load_scaling_factor;
    end

    % Sum the individual scaled loads to get total power
    P_total = sum(load_kW);
    Q_total = sum(load_kVAR);

    % Charging/Discharging logic
    if is_peak && SOC_value > 0
        % Discharge during peak hours
        P_BESS = 50*load_scaling_factor;
        DSSText.Command = ['Storage.BESS1.kW=', num2str(P_BESS)];
        DSSText.Command = 'edit Storage.BESS1 State=DISCHARGING';
        total_discharging_energy = total_discharging_energy + (P_BESS * (time_step / 3600));  % Accumulate discharging energy
    elseif ~is_peak && SOC_value < 100
        % Charging during off-peak hours
        P_BESS = -30*load_scaling_factor;  % Charging power
        DSSText.Command = ['Storage.BESS1.kW=', num2str(P_BESS)];
        DSSText.Command = 'edit Storage.BESS1 State=CHARGING';
        total_charging_energy = total_charging_energy + (-P_BESS * (time_step / 3600));  
        %P_total = -P_total;  % Energy flowing back to grid
        grid_energy_consumed = grid_energy_consumed + (P_total * (time_step / 3600));  % kWh consumed from grid
    elseif ~is_peak && SOC_value >= 100
        % Discharge during off-peak hours if SOC is full
        P_BESS = 60*load_scaling_factor;
        DSSText.Command = ['Storage.BESS1.kW=', num2str(P_BESS)];
        DSSText.Command = 'edit Storage.BESS1 State=DISCHARGING';
        total_discharging_energy = total_discharging_energy + (P_BESS * (time_step / 3600));  
    else
        % Idle state when SOC is at full charge or during peak hours
        DSSText.Command = 'edit Storage.BESS1 State=IDLING';
    end

    set_param('COSIMsim/SOC_prev', 'Value', num2str(SOC_value));  % Update SOC
    set_param('COSIMsim/Battery_change', 'Value', num2str(P_BESS));      % Update P_BESS
    set_param('COSIMsim/Network Voltages Phase-A ', 'Value', ['[', num2str(V1'), ']']);
    set_param('COSIMsim/Network Voltages Phase-B', 'Value', ['[', num2str(V2'), ']']);
    set_param('COSIMsim/Network Voltages Phase-C', 'Value', ['[', num2str(V3'), ']']);

    % Step the Simulink simulation
    set_param('COSIMsim', 'SimulationCommand', 'step');

    % Solve the circuit in OpenDSS
    DSSText.Command = 'solve';
    DSSText.Command = '? Storage.BESS1.%stored';
    SOC_value = str2double(DSSText.Result);
    SOC_value = max(0, min(100, SOC_value)); 

    fprintf(['Time: %.2f hours, SOC: %.2f%%, P_BESS: %.2f kW, ', ...
             'P_total: %.2f kW, Q_total: %.2f kVAR\n'], ...
             simTime / 3600, SOC_value, P_BESS, P_total, Q_total);

    % Increment simulation time
    simTime = simTime + time_step;
end

% Stop Simulink simulation
set_param('COSIMsim', 'SimulationCommand', 'stop');

% Calculating total cost based on grid consumption
unit_price = 56;  % Price per kWh in PKR
total_cost_grid = grid_energy_consumed * unit_price*30*6;  % Total cost in PKR
total_charging_energy_month=total_charging_energy*30*6;
total_discharging_energy_month=total_discharging_energy*30*6;
total_charging_cost=total_charging_energy_month*unit_price;
total_discharging_cost=total_discharging_energy_month*unit_price;
Saving=total_charging_cost-total_discharging_cost;
disp(['Total Energy Usage from Grid Over Six Months: ', num2str(grid_energy_consumed ), ' kWh']);
disp(['Total Charging Energy Consumption (6 Months): ', num2str(total_charging_energy_month), ' kWh']);
disp(['Total Discharging EnergyConsumption (6 Months) ', num2str(total_discharging_energy_month), ' kWh']);
disp(['Six-Month Grid Energy Consumption Cost: ', num2str(total_cost_grid), ' PKR']);
disp(['Total Savings Over 6 Months (PKR): ', num2str(Saving), ' PKR']);
