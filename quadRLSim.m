% Model parameters
S.mb = 1.477; % Mass of UAV
S.d = 0.263; % Arm Length (Rotor and COM of UAV)
S.c = 8.004e-4; % Drag Factor
S.Ib = [0.01152; 0.01152; 0.0218]; % Moment of Inertia of UAV
% S.Ib = [0.01152 0 0;0 0.01152 0;0 0 0.0218];
S.m1 = 0.05; % Mass of First Link
S.m2 = 0.05; % Mass of Second Link
S.l1 = 0.5; % Length of First Link
S.l2 = 0.5; % Length of Second Link
S.g = 9.81; % Gravity

% Control Parameters
K.Kp = 11.9;
K.Kv = 4.443;
K.KR = .1;
K.K_omega = 1;
% K.Kp = 1;
% K.Kv = 7;
% K.KR = .03;
% K.K_omega = 1.5;
S.K = K;
S.dt = 1/1000;
numObs = 16;
    obsInfo = rlNumericSpec([numObs 1]);
obsInfo.Name = 'Quad States';
obsInfo.Description = 'x,y,z,xdot,ydot,zdot,r,p,y,wx,wy,wz';
%
thrust = (1.477 + 0.05 + 0.05) * 9.81/4;
numAct = 4;
actInfo = rlNumericSpec([1 numAct]);
actInfo.Name = 'Quad Action';
actInfo.LowerLimit = ones(1, numAct);
actInfo.UpperLimit = 5*ones(1, numAct);

%actInfo = rlFiniteSetSpec({[thrust, thrust, thrust, thrust]});
%actInfo.Name = 'Quad Action';
%%
statePath = [
    featureInputLayer(numObs,'Normalization','none','Name','observation')
    fullyConnectedLayer(64,'Name','CriticStateFC1')
    reluLayer('Name', 'CriticRelu1')
    fullyConnectedLayer(64,'Name','CriticStateFC2')];
actionPath = [
    featureInputLayer(numAct,'Normalization','none','Name','action')
    fullyConnectedLayer(64,'Name','CriticActionFC1','BiasLearnRateFactor',0)];
commonPath = [
    additionLayer(2,'Name','add')
    reluLayer('Name','CriticCommonRelu')
    fullyConnectedLayer(1,'Name','CriticOutput')];

criticNetwork = layerGraph();
criticNetwork = addLayers(criticNetwork,statePath);
criticNetwork = addLayers(criticNetwork,actionPath);
criticNetwork = addLayers(criticNetwork,commonPath);
    
criticNetwork = connectLayers(criticNetwork,'CriticStateFC2','add/in1');
criticNetwork = connectLayers(criticNetwork,'CriticActionFC1','add/in2');

criticOpts = rlRepresentationOptions('LearnRate',1e-03,'GradientThreshold',1,'UseDevice',"gpu");
critic = rlQValueRepresentation(criticNetwork,obsInfo,actInfo,'Observation',{'observation'},'Action',{'action'},criticOpts);
%critic = rlValueRepresentation(criticNetwork,obsInfo,actInfo,'Observation',{'observation'},'Action',{'action'},criticOpts);
actorNetwork = [
    featureInputLayer(numObs,'Normalization','none','Name','observation')
    fullyConnectedLayer(32,'Name','ActorFC1')
    reluLayer('Name','ActorRelu1')
    fullyConnectedLayer(32,'Name','ActorFC2')
    reluLayer('Name','ActorRelu2')
    fullyConnectedLayer(32,'Name','ActorFC3')
    reluLayer('Name','ActorRelu3')
    fullyConnectedLayer(numAct,'Name','ActorFC4')
    tanhLayer('Name','ActorTanh')
    scalingLayer('Name','ActorScaling','Scale',max(actInfo.UpperLimit))];

actorOpts = rlRepresentationOptions('LearnRate',1e-04,'GradientThreshold',1,'UseDevice',"gpu");

actor = rlDeterministicActorRepresentation(actorNetwork,obsInfo,actInfo,'Observation',{'observation'},'Action',{'ActorScaling'},actorOpts);
%actor = rlStochasticActorRepresentation(actorNetwork,obsInfo,actInfo,'Observation',{'observation'},actorOpts);
agentOpts = rlDDPGAgentOptions(...
    'SampleTime',0.01,...
    'TargetSmoothFactor',1e-3,...
    'ExperienceBufferLength',1e6,...
    'DiscountFactor',0.99,...
    'MiniBatchSize',128);
agentOpts.NoiseOptions.Variance = 0.6;
agentOpts.NoiseOptions.VarianceDecayRate = 1e-5;

%Define Environment
env = rlFunctionEnv(obsInfo,actInfo,'myStepFunction','myResetFunction');

agent = rlDDPGAgent(actor,critic,agentOpts);

%agent = rlACAgent(actor,critic);
%%
%Define Environment
env = rlFunctionEnv(obsInfo,actInfo,'myStepFunction','myResetFunction');

%Define Agent
initOpts = rlAgentInitializationOptions('NumHiddenUnit', 64);

agent = rlACAgent(obsInfo,actInfo);

critic = getCritic(agent);
critic.Options.LearnRate = 1e-2;
critic.Options.GradientThreshold = 1;
critic.Options.UseDevice = "gpu";
agent  = setCritic(agent,critic);

actor = getActor(agent);
actor.Options.LearnRate = 1e-2;
actor.Options.GradientThreshold = 1;
actor.Options.UseDevice = "gpu";
agent = setActor(agent,actor);

%%
trainOpts = rlTrainingOptions(...
    'MaxEpisodes',1000000, ...
    'MaxStepsPerEpisode',10000, ...
    'Verbose',false, ...
    'Plots','training-progress',...
    'StopTrainingCriteria',"AverageReward",...
    'StopTrainingValue',10000000);  

trainingStats = train(agent,env,trainOpts);
%%
simOptions = rlSimulationOptions('MaxSteps',5000);
experience = sim(env,agent,simOptions);
%
t = experience.Observation.QuadStates.Time;
xsave = squeeze(experience.Observation.QuadStates.Data(:,1,:));
action = squeeze(experience.Action.QuadAction.Data(1,:,:));
size(xsave)
figure(1)
plot(t, xsave(1,:),'.')
grid on
hold on
plot(t, xsave(2,:),'.')
plot(t, xsave(3,:),'.')
figure(2)
plot(t(2:end), action(1,:),'.')
hold on
plot(t(2:end), action(2,:),'o')
plot(t(2:end), action(3,:),'x')
plot(t(2:end), action(4,:),'.')
grid on

%% Video generator
figure(1);
filename = 'myVideo.avi';
%video_gen(t, xsave', filename, 30)
video_gen2(t(1:end-1), xsave(:,1:end-1)', S, filename, 30)