clear;  %Remove all varialbes from current Workspace
clc;    %Clear all text from the Command Window  

%Prompt user for simulation length and time step
tend = input("Length of simulation (in days): ");  
tstep = input("Time-step (delta t) for simulation length (in days): ");

%Prompt user for population inputs
H = input("Initial total COVID-free population: ");    
N = input("Number of new persons per time-step: ");
Neu1 = input("Number of exposed persons on day one (Neu1): ");
Ne = input("Average # of unexposed persons who an exposed person exposes (Ne): ");
tv = input("Time when vaccinations become available (tv): ");
Nvmax = input("Maximum # of vaccinations that can be delivered per day (Nvmax): ");

%Prompt user for alpha values
ah = input("Fraction of Persons Who Refuse Vaccination (ah): ");
av = input("Fraction of Unvaccinated Persons Who Get Vaccinated per Day (av): ");
adn = input("Fraction of Persons Who Die of Non-COVID Causes per Day (adn): "); 
avi = input("Fraction of Vaccinated Persons Who Are Immune (avi): "); 
aui = input("Fraction of Unvaccinated Persons Who Are Immune (aui): ");
avsq = input("Fraction of Sick and Vaccinated Persons Who Require Hospitalization (avsq) *avsq+avsl must be < 1*: ");
avsl = input("Fraction of Sick and Vaccinated Persons Who Get Long COVID (avsl): ");
avqd = input("Fraction of Hospitalized Vaccinated Persons Who Die (avqd) *avqd+avql must be < 1*: ");
avql = input("Fraction of Hospitalized Vaccinated Persons Who Contract Long COVID (avql): ");
ausl = input("Fraction of Sick and Unvaccinated Persons Who Get Long COVID (ausl) *ausq+ausl must be < 1*: ");
ausq = input("Fraction of Sick and Unvaccinated Persons Who Require Hospitalization (ausq): ");
auqd = input("Fraction of Hospitalized Unvaccinated Persons Who Die (auqd) *auqd+auql must be < 1*: ");
auql = input("Fraction of Hospitalized Unvaccinated Persons Who Contract Long COVID (auql): ");

%Prompt user for delta values
dte = input("Average gestation period after exposure (dte): ");
dtvs = input("Average duration of sickness for vaccinated persons (dtvs): ");
dtus = input("Average duration of sickness for unvaccinated persons (dtus): ");
dtvq = input("Average hospital stay for vaccinated persons (dtvq): ");
dtuq = input("Average hospital stay for unvaccinated persons (dtuq): ");

%Assign variables and create variable arrays of zeros which will represent the initial state (t=1) for all the variables with the exception of Hu, Hr, and Eu 
Hu = zeros(1, tend+1);  %Initial # of unvaccinated persons who accept vaccination
Hr = zeros(1, tend+1);  %Initial # of persons who refuse vaccination=ah*H
Hv = zeros(1, tend+1);  %Initial # of persons who are vaccinated
Ht = Hv + Hu + Hr;      %Initial # of total healthy population   
Dn = zeros(1, tend+1);  %Initial # of persons who have died of non-COVID causes
Ev = zeros(1, tend+1);  %Initial # of vaccinated persons who are exposed
Eu = zeros(1, tend+1);  %Initial # of unvaccinated persons who are exposed
Sv = zeros(1, tend+1);  %Initial # of vaccinated persons who are sick
Su = zeros(1, tend+1);  %Initial # of unvaccinated persons who are sick
Qv = zeros(1, tend+1);  %Initial # of vaccinated persons who are hospitalized 
Qu = zeros(1, tend+1);  %Initial # of unvaccinated persons who are hospitalized
L = zeros(1, tend+1);   %Initial # of persons who have long COVID
Dc = zeros(1, tend+1);  %Initial # of persons who have died from COVID
I = zeros(1, tend+1);   %Initial # of persons who are immune to COVID

%Initiation of population (initial states for Hu, Hr, and Eu at t=1)
Hu(1) = (1-ah)*(H-Neu1);
Hr(1) = ah*(H-Neu1);
Eu(1) = Neu1;

t = 1;  %Assign indexing variable and set initial value

%Set up "for loop" that runs the change of states simulation
for t = 1:tstep:tend 
    Ht(t) = Hv(t) + Hu(t) + Hr(t);
    Hfu(t) = (Hu(t))/(Hu(t) + Hr(t));
    Hfr(t) = (Hr(t))/(Hu(t) + Hr(t));
    P(t) = Ht(t) + L(t) + I(t) + Eu(t) + Ev(t);
    
    %Equations that compute the flow rates in and out of each state (q's)
    q1 = (1 - ah)*N;
    q2 = ah*N;
    
    if t < tv
        q3 = 0;
    elseif t >= tv 
        q3 = min((av*Hu(t)), Nvmax);
    end
    
    q4 = adn*Hu(t);
    q5 = adn*Hr(t);
    q6 = adn*Hv(t);
    q7 = (1 - aui)*(Ne/dte)*(Ev(t) + Eu(t))*(Hr(t)/P(t));
    q8 = (1 - aui)*(Ne/dte)*(Ev(t) + Eu(t))*(Hu(t)/P(t));
    q9 = (1 - avi)*(Ne/dte)*(Ev(t) + Eu(t))*(Hv(t)/P(t));
    q10 = adn*I(t);
    q11 = adn*L(t);
    q12 = avi*(Ne/dte)*(Ev(t) + Eu(t))*(Hv(t)/P(t));
    q13u = aui*(Ne/dte)*(Ev(t) + Eu(t))*(Hu(t)/P(t));
    q13r = aui*(Ne/dte)*(Ev(t) + Eu(t))*(Hr(t)/P(t));
    q14 = Ev(t)/dte;
    q20 = avsl*(Sv(t)/dtvs);
    q22 = avsq*(Sv(t)/dtvs);
    q17 = (Sv(t)/dtvs) - q20 - q22;
    q26 = avqd*(Qv(t)/dtvq);
    q23 = avql*(Qv(t)/dtvq);
    q15 = (Qv(t)/dtvq) - q23 - q26;
    q19 = Eu(t)/dte;
    q25 = ausq*(Su(t)/dtus);
    q21 = ausl*(Su(t)/dtus);
    q18 = (Su(t)/dtus) - q21 - q25;
    q27 = auqd*(Qu(t)/dtuq);
    q24 = auql*(Qu(t)/dtuq);
    q16 = (Qu(t)/dtuq) - q24 - q27;
    
    %Equations that compute state variables
    Hu(t + 1) = Hu(t) + q1 - q3 - q4 - q8 - q13u;
    Hr(t + 1) = Hr(t) + q2 - q5 - q7 - q13r;
    Hv(t + 1) = Hv(t) + q3 - q6 - q9 - q12;	
    Dn(t + 1) = Dn(t) + q4 + q5 + q6 + q10 + q11;
    Ev(t + 1) = Ev(t) + q9 - q14;
    Eu(t + 1) = Eu(t) + q7 + q8 - q19;
    Sv(t + 1) = Sv(t) + q14 - q17 - q20 - q22;
    Su(t + 1) = Su(t) + q19 - q18 - q21 - q25;
    Qv(t + 1) = Qv(t) + q22 - q15 - q23 - q26;
    Qu(t + 1) = Qu(t) + q25 - q16 - q24 - q27;
    L(t + 1) = L(t) + q20 + q23 + q24 + q21 - q11;
    Dc(t + 1) = Dc(t) + q26 + q27;
    I(t + 1) = I(t) + q12 + q15 + q17 + q18 + q16 + q13u + q13r - q10;
end

disp("Number of COVID-19 Deaths in Virginia (March 7, 2020 - November 11, 2022): ")
disp(Dc(tend+1))



%Plot Hv vs t; Hu vs t; Hr vs t
x = linspace(1,tend+1,tend+1);  %X-axis: time (same for ALL plots)
plot(x,Hv,'c', x,Hu,'m', x,Hr,'g')

%Plot details
xlabel('Time (Days)')
ylabel('Number of People')
title('Vaccination Status vs Time')
legend('Hv: Vaccinated', 'Hu: Unvaccinated but Willing', 'Hr: Unvaccinated and Refusing')
 


%New graph window
figure

%Plot Ev vs t; Eu vs t
plot(x,Ev,'c', x,Eu,'m')  

%Plot details
xlabel('Time (Days)')
ylabel('Number of People')
title('COVID-19 Exposure Among Vaccinated and Unvaccinated Population vs Time')
legend('Ev: Vaccinated and Exposed', 'Eu: Unvaccinated and Exposed')



%New graph window
figure

%Plot Sv vs t; Su vs t
plot(x,Sv,'c', x,Su,'m')

%Plot details
xlabel('Time (Days)')
ylabel('Number of People')
title('COVID-19 Infection Among Vaccinated and Unvaccinated Population vs Time')
legend('Sv: Vaccinated and Sick', 'Su: Unvaccinated and Sick')



%New graph window
figure

%Plot Qv vs t; Qu vs t
plot(x,Qv,'c', x,Qu,'m')

%Plot details
xlabel('Time (Days)')
ylabel('Number of People')
title('COVID-19 Hospitalizations Among Vaccinated and Unvaccinated Population vs Time')
legend('Qv: Vaccinated and Hospitalized', 'Qu: Unvaccinated and Hospitalized')



%New graph window
figure

%Plot Dn vs t; Dc vs t
plot(x,Dn,'c', x,Dc,'m')

%Plot details
xlabel('Time (Days)')
ylabel('Number of People')
title('Deaths vs Time')
legend('Dn: Non-COVID Related Deaths', 'Dc: COVID Deaths')



%New graph window
figure

%Plot L vs t; I vs t
plot(x,L,'c', x,I,'m')

%Plot deatils
xlabel('Time (Days)')
ylabel('Number of People')
title('Effects of COVID-19 vs Time')
legend('L: Developed Long COVID', 'I: Developed COVID Immunity')



%New graph window
figure

%Plot validity check
ValidityCheck = Hv + Hu + Hr + Dn + Ev + Eu + I + Sv + Su + L...
    + Qv + Qu + Dc;
y1 = ValidityCheck;   

plot(x,y1)  

%Plot details
xlabel('Time (Days)')
ylabel('Number of People')
title('Validity Check: Plot should increase linearly at number of new persons per day')



%New graph window
figure

%Plot for Question #1: Dependence Between Vaccination Rate and COVID-19 Death Rate
plot(x,Hv,'c', x,Dc,'m')

%Plot details
xlabel('Time (Days)')
ylabel('Number of People')
title('Dependence Between Vaccination Rate and COVID-19 Death Rate')
legend('Hv: Number of People Vaccinated', 'Dc: Number of COVID Deaths')



%New graph window
figure

%Plot for Question #2: Dependence Between Population's Trust in the Vaccine and Vaccination Rate
plot(x,Hv,'c', x,Sv,'m', x,Su,'g')

%Plot details
xlabel('Time (Days)')
ylabel('Number of People')
title("Dependence Between Population's Trust in the Vaccine and Vaccination Rate" )
legend('Hv: Number of People Vaccinated', 'Sv: Vaccinated People With COVID', 'Su: Unvaccinated People With COVID')



%New graph window
figure

%Plot for Question #2: Dependence Between Population's Trust in the Vaccine and Vaccination Rate
plot(x,Hv,'c', x,Qv,'m', x,Qu,'g')

%Plot details
xlabel('Time (Days)')
ylabel('Number of People')
title("Dependence Between Population's Trust in the Vaccine and Vaccination Rate" )
legend('Hv: Number of People Vaccinated', 'Qv: Vaccinated People Hospitalized', 'Qu: Unvaccinated People Hospitalized')



%New graph window
figure

%Plots for Question #3: Dependence Between Masking Policies and COVID-19 Deaths
plot(x,Dc,'c', x,Dn,'m')

%Plot details
xlabel('Time (Days)')
ylabel('Number of People')
title('Dependence Between Masking Policies and COVID-19 Deaths')
legend('Dc: COVID-19 Deaths With Adequate Masking Policies', 'Dn: Non-COVID Deaths')

%Plot details
% xlabel('Time (Days)')
% ylabel('Number of People')
% title('Dependence Between Masking Policies and COVID-19 Deaths')
% legend('Dc: COVID-19 Deaths With Inadequate Masking Policies', 'Dn: Non-COVID Deaths')
