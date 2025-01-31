%% PART 1
% Input data
maturities = [1/12, 3/12, 6/12, 9/12, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 15, 20, 25, 30]; % in years
swap_rates = [2.516, 2.647, 3.08, 3.14, 3.239, 2.833, 2.625, 2.463, 2.405, 2.355, ...
              2.323, 2.313, 2.319, 2.378, 2.535, 2.517, 2.436, 2.444] / 100; % as decimals

% Define Nelson-Siegel-Svensson (NSS) model
nss_curve = @(params, tau) ...
    params(1) + ...
    params(2) * (1 - exp(-tau / params(5))) ./ (tau / params(5)) + ...
    params(3) * ((1 - exp(-tau / params(5))) ./ (tau / params(5)) - exp(-tau / params(5))) + ...
    params(4) * ((1 - exp(-tau / params(6))) ./ (tau / params(6)) - exp(-tau / params(6)));

% Objective function for optimization
objective = @(params) sum((nss_curve(params, maturities) - swap_rates).^2);

% Initial guesses for NSS parameters
initial_guess = [0.03, -0.02, 0.02, -0.01, 1.0, 2.0];

% Parameter bounds (optional, to guide optimization)
lb = [-Inf, -Inf, -Inf, -Inf, 0.01, 0.01];
ub = [Inf, Inf, Inf, Inf, 10, 10];

% Optimize using fmincon
options = optimoptions('fmincon', 'Display', 'iter', 'Algorithm', 'sqp');
params = fmincon(objective, initial_guess, [], [], [], [], lb, ub, [], options);

% Interpolate quarterly swap rates
quarterly_maturities = (0.25:0.25:30); % Quarterly intervals
interpolated_rates = nss_curve(params, quarterly_maturities);

% Bootstrap zero-coupon bond prices
num_quarters = length(quarterly_maturities);
discount_factors = zeros(1, num_quarters);

for i = 1:num_quarters
    tau = quarterly_maturities(i);
    rate = interpolated_rates(i);
    
    % For maturities under 1 year, no bootstrap required
    if tau <= 1
        discount_factors(i) = 1 / ((1 + rate) ^ tau);
    else
        % Solve for the discount factor using swap rate definition
        sum_prev_dfs = sum(discount_factors(1:i-1));
        discount_factors(i) = (1 - rate * sum_prev_dfs) / (1 + rate);
    end
end

% Calculate Zero Rates from Discount Factors
zero_rates = -log(discount_factors) ./ quarterly_maturities;

% Plot fitted NSS curve
figure
plot(maturities, swap_rates, 'o', quarterly_maturities, interpolated_rates, '-');
legend('Market Swap Rates', 'Interpolated NSS Curve');
xlabel('Maturity (Years)');
ylabel('Swap Rate (%)');
title('Nelson-Siegel-Svensson Model Calibration')

% Plot Discount Factors (ZCB Prices)
figure
plot(quarterly_maturities, discount_factors)
legend('ZCB Price')
xlabel('Maturity (Years)')
ylabel('Price')
title('Bootstrapped Zero-Coupon Bond Prices for Different Maturities')

%% PART 2
% Input data
Settle = datetime(2023,4,26); % valuation date for the CDS
Spread_Time = [0.5 1 2 3 4 5 7 10 20 30]';  % CDS maturities
Spread = {
    [24.130 30.280 40.800 51.230 61.900 72.590 85.030 95.670 106.920 115.570]',  % Banco Santander
    [19.570 26.840 39.600 52.190 65.310 78.210 100.980 122.460 144.560 160.360]', % Eni
    [93.560 134.260 208.920 292.940 372.710 446.770 527.180 574.230 612.050 621.800]', % Ziggo
    [93.000 119.940 139.830 159.550 198.290 236.070 269.500 291.570 313.450 325.460]', % Lufthansa
    [73.160 83.130 150.590 215.880 273.440 327.820 395.740 413.030 430.260 436.880]', % Renault
    [14.840 20.110 27.430 34.670 41.520 48.290 58.350 68.860 80.010 88.960]'  % Allianz
};

% Zero-coupon bond data for interpolation
Zero_Time = quarterly_maturities';
Zero_Rate = zero_rates';
%Zero_Rate = discount_factors';

% Convert Zero-Time to dates
Zero_Dates = daysadd(datenum(Settle), 360 * Zero_Time, 1);
ZeroData = [Zero_Dates, Zero_Rate];

% Loop over all bonds and calculate hazard rates and default probabilities
ProbDataAll = [];
HazDataAll = [];
CompanyNames = {'Banco Santander', 'Eni', 'Ziggo', 'Lufthansa', 'Renault', 'Allianz'};

for i = 1:length(Spread)
    % Prepare market data for each company
    Market_Dates = daysadd(datenum(Settle), 360 * Spread_Time, 1);
    MarketData = [Market_Dates, Spread{i}];  % Convert spreads to decimals
    
    % Run CDS bootstrapping for each bond
    [ProbData, HazData] = cdsbootstrap(ZeroData, MarketData, Settle);
    
    % Store results for plotting
    ProbDataAll = [ProbDataAll, ProbData(:, 2)];  % Default probabilities for all companies
    HazDataAll = [HazDataAll, HazData(:, 2)];    % Hazard rates for all companies
end

% Plot default probabilities
figure;
hold on;
for i = 1:length(Spread)
    plot(Spread_Time, ProbDataAll(:, i), 'DisplayName', CompanyNames{i});
end
title("Default Probability for Each Company");
legend('show');
xlabel('Maturity (Years)');
ylabel('Default Probability');
hold off;

% Plot hazard rates
figure;
hold on;
for i = 1:length(Spread)
    stairs(Spread_Time, HazDataAll(:, i), 'DisplayName', CompanyNames{i});
end
title("Hazard Rate for Each Company");
legend('show');
xlabel('Maturity (Years)');
ylabel('Hazard Rate');
hold off;
