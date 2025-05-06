% Battery profile - Grid power kWh 
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

% Initial parameters for Battery Storage System (BESS)
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

loadProfile = [0.8, 0.9, 1.0, 1.1, 1.3, 1.5, 1.8, 2.0, 2.3, 2.4, 2.5, 2.7, ...
               2.9, 3.0, 2.8, 2.7, 2.5, 2.2, 2.0, 1.8, 1.7, 1.6, 1.4, 1.2, 1.0];


% Set initial battery charging/discharging parameters
charging_power = 10;  % kW 
discharging_power = 30;  % 
target_SOC_max = 90;  % Max SOC for charging
target_SOC_min = 90;  % Min SOC for discharging

SOC_values = [];  % Store SOC at each step
grid_energy_consumed = 0;  % Total energy consumed from grid (in kWh)
total_charging_energy = 0;  % Total charging energy (kWh)
total_discharging_energy = 0;  % Total discharging energy (kWh)

% Start and pause Simulink simulation
set_param('COSIMsim', 'SimulationCommand', 'start');
set_param('COSIMsim', 'SimulationCommand', 'pause');
load_names = {'Load.671', 'Load.634a', 'Load.634b', 'Load.634c', 'Load.645', 'Load.646', 'Load.692', ...
              'Load.675a', 'Load.675b', 'Load.675c', 'Load.611', 'Load.652', 'Load.670a', 'Load.670b', 'Load.670c'};

load_kW = zeros(1, length(load_names));
load_kVAR = zeros(1, length(load_names));

% Main simulation loop with real-time updates
while simTime < endTime
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
    S_total=sqrt(P_total^2+Q_total^2);

    % Charging/Discharging logic based on SOC value
    DSSText.Command = '? Storage.BESS1.%stored';  % Fetch current SOC
    SOC_value = str2double(DSSText.Result);       % Update SOC variable

    if SOC_value < target_SOC_max
        % If SOC is below 90%, charge the battery
        P_BESS = -charging_power+load_scaling_factor;  
        DSSText.Command = ['Storage.BESS1.KW=', num2str(P_BESS)];
        DSSText.Command = 'edit Storage.BESS1 State=CHARGING';
        %P_total = -P_total;  

        total_charging_energy = total_charging_energy + (-P_BESS * (time_step / 3600));  % Accumulate charging energy
        grid_energy_consumed = grid_energy_consumed + (P_total * (time_step / 3600));  % kWh
    elseif SOC_value > target_SOC_min
        P_BESS = discharging_power*load_scaling_factor;  
        DSSText.Command = ['Storage.BESS1.KW=', num2str(P_BESS)];
        DSSText.Command = 'edit Storage.BESS1 State=DISCHARGING';
        
        % Energy supplied by the battery (discharging power)
        total_discharging_energy = total_discharging_energy + (discharging_power * (time_step / 3600));  % Accumulate discharging energy
        
    else
        P_BESS = 0;  % Idle power
        DSSText.Command = 'edit Storage.BESS1 State=IDLING';
    end

    % Solve the circuit in OpenDSS to update SOC (for battery)
    DSSText.Command = 'solve';  % This updates the state of the battery in OpenDSS
    DSSText.Command = '? Storage.BESS1.%stored';  % Fetch updated SOC from OpenDSS
    SOC_value = str2double(DSSText.Result);  % Update SOC variable
    SOC_value = max(0, min(99, SOC_value));  

    set_param('COSIMsim/SOC_prev', 'Value', num2str(SOC_value));  % Update SOC
    set_param('COSIMsim/Battery_change', 'Value', num2str(P_BESS));      % Update P_BESS
    set_param('COSIMsim/Network Voltages Phase-A ', 'Value', ['[', num2str(V1'), ']']);
    set_param('COSIMsim/Network Voltages Phase-B', 'Value', ['[', num2str(V2'), ']']);
    set_param('COSIMsim/Network Voltages Phase-C', 'Value', ['[', num2str(V3'), ']']);

    set_param('COSIMsim', 'SimulationCommand', 'step');

    SOC_values = [SOC_values, SOC_value];  % Store SOC value at each step

    fprintf(['Time: %.2f hours, SOC: %.2f%%, ', ...
              'Grid Power: %.2f kW, Q_total: %.2f kVAR, S_total: %.2f kVA\n'], ...
             simTime / 3600, SOC_value, P_total, Q_total, S_total);

    % Increment simulation time
    simTime = simTime + time_step;
end

% Stop Simulink simulation
set_param('COSIMsim', 'SimulationCommand', 'stop');
disp('Simulation complete.');

% Calculate total cost based on grid consumption
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
