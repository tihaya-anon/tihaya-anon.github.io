---
title: "Microeconomics"
description: "A compact formula sheet for core microeconomics."
---

{{< katex >}}

## Choice and opportunity cost

Opportunity cost:

$$
OC_x = \frac{\Delta y}{\Delta x}
$$

Production possibilities frontier:

$$
F(x,y)=0
$$

Marginal rate of transformation:

$$
MRT_{xy} = -\frac{dy}{dx}
$$

Comparative advantage:

$$
OC_x^A < OC_x^B
$$

Efficient allocation:

$$
MRS_{xy}=MRT_{xy}
$$

## Demand, supply, and equilibrium

Linear demand and supply:

$$
Q_d = a-bP
$$

$$
Q_s = c+dP
$$

Market equilibrium:

$$
Q_d(P^*) = Q_s(P^*)
$$

Equilibrium price for linear demand and supply:

$$
P^* = \frac{a-c}{b+d}
$$

Equilibrium quantity:

$$
Q^* = Q_d(P^*) = Q_s(P^*)
$$

Inverse demand and supply:

$$
P_D(Q)
$$

$$
P_S(Q)
$$

Shortage under a price ceiling \( \bar P < P^* \):

$$
\text{Shortage}=Q_d(\bar P)-Q_s(\bar P)
$$

Surplus under a price floor \( \underline P > P^* \):

$$
\text{Surplus}=Q_s(\underline P)-Q_d(\underline P)
$$

## Elasticity

Point price elasticity of demand:

$$
\epsilon_d = \frac{dQ_d}{dP}\frac{P}{Q_d}
$$

Arc price elasticity of demand:

$$
\epsilon_d =
\frac{\frac{Q_2-Q_1}{(Q_1+Q_2)/2}}{\frac{P_2-P_1}{(P_1+P_2)/2}}
$$

Price elasticity of supply:

$$
\epsilon_s = \frac{dQ_s}{dP}\frac{P}{Q_s}
$$

Income elasticity:

$$
\epsilon_I = \frac{dQ}{dI}\frac{I}{Q}
$$

Cross-price elasticity:

$$
\epsilon_{xy} = \frac{dQ_x}{dP_y}\frac{P_y}{Q_x}
$$

Total revenue:

$$
TR = P \cdot Q
$$

Marginal revenue from elasticity:

$$
MR = P\left(1+\frac{1}{\epsilon_d}\right)
$$

## Consumer theory

Budget constraint:

$$
p_xx+p_yy=I
$$

Budget line slope:

$$
\frac{dy}{dx}=-\frac{p_x}{p_y}
$$

Utility maximization:

$$
\max_{x,y} U(x,y)
\quad \text{s.t.} \quad
p_xx+p_yy \le I
$$

Marginal utility:

$$
MU_x = \frac{\partial U}{\partial x}
$$

Marginal rate of substitution:

$$
MRS_{xy} = \frac{MU_x}{MU_y}
$$

Interior consumer optimum:

$$
MRS_{xy}=\frac{p_x}{p_y}
$$

Equivalent marginal utility condition:

$$
\frac{MU_x}{p_x}=\frac{MU_y}{p_y}
$$

Lagrangian:

$$
\mathcal{L}=U(x,y)+\lambda(I-p_xx-p_yy)
$$

First-order conditions:

$$
MU_x=\lambda p_x
$$

$$
MU_y=\lambda p_y
$$

Indirect utility:

$$
v(p,I)=\max_x U(x)
\quad \text{s.t.} \quad
p \cdot x \le I
$$

Expenditure function:

$$
e(p,u)=\min_x p \cdot x
\quad \text{s.t.} \quad
U(x) \ge u
$$

Roy's identity:

$$
x_i(p,I) =
-\frac{\partial v(p,I)/\partial p_i}{\partial v(p,I)/\partial I}
$$

Shephard's lemma:

$$
h_i(p,u)=\frac{\partial e(p,u)}{\partial p_i}
$$

Slutsky equation:

$$
\frac{\partial x_i}{\partial p_j}
=
\frac{\partial h_i}{\partial p_j}
-
x_j\frac{\partial x_i}{\partial I}
$$

## Surplus, welfare, taxes, and subsidies

Consumer surplus:

$$
CS=\int_0^{Q^*}\left(P_D(q)-P^*\right)dq
$$

Producer surplus:

$$
PS=\int_0^{Q^*}\left(P^*-P_S(q)\right)dq
$$

Total surplus:

$$
TS=CS+PS
$$

Deadweight loss:

$$
DWL=TS_{\text{efficient}}-TS_{\text{actual}}
$$

Linear deadweight loss:

$$
DWL=\frac{1}{2}\times \text{wedge}\times \Delta Q
$$

Per-unit tax wedge:

$$
P_b-P_s=t
$$

Tax equilibrium:

$$
Q_d(P_b)=Q_s(P_s)
$$

Tax revenue:

$$
T=tQ_t
$$

Tax deadweight loss:

$$
DWL=\frac{1}{2}t(Q^*-Q_t)
$$

Per-unit subsidy wedge:

$$
P_s-P_b=s
$$

Government subsidy cost:

$$
G=sQ_s
$$

## Production and cost

Production function:

$$
q=f(K,L)
$$

Marginal product of labor:

$$
MP_L=\frac{\partial q}{\partial L}
$$

Marginal product of capital:

$$
MP_K=\frac{\partial q}{\partial K}
$$

Average product of labor:

$$
AP_L=\frac{q}{L}
$$

Diminishing marginal returns:

$$
\frac{\partial^2 f}{\partial L^2}<0
$$

Marginal rate of technical substitution:

$$
MRTS_{LK}=\frac{MP_L}{MP_K}
$$

Cost minimization:

$$
\min_{K,L} wL+rK
\quad \text{s.t.} \quad
f(K,L)\ge q
$$

Cost-minimizing input condition:

$$
\frac{MP_L}{w}=\frac{MP_K}{r}
$$

Total cost:

$$
TC(q)=FC+VC(q)
$$

Average fixed cost:

$$
AFC(q)=\frac{FC}{q}
$$

Average variable cost:

$$
AVC(q)=\frac{VC(q)}{q}
$$

Average total cost:

$$
ATC(q)=\frac{TC(q)}{q}
$$

Marginal cost:

$$
MC(q)=\frac{dTC(q)}{dq}
$$

Cobb-Douglas production:

$$
q=AK^\alpha L^\beta
$$

Returns to scale:

$$
f(tK,tL)
\begin{cases}
>tf(K,L) & \text{increasing returns} \\
=tf(K,L) & \text{constant returns} \\
<tf(K,L) & \text{decreasing returns}
\end{cases}
$$

## Firms and market structure

Profit:

$$
\pi(q)=TR(q)-TC(q)
$$

Revenue:

$$
TR(q)=P(q)q
$$

Marginal revenue:

$$
MR(q)=\frac{dTR(q)}{dq}
$$

Profit maximization:

$$
MR(q^*)=MC(q^*)
$$

Perfect competition:

$$
P=MR=MC
$$

Competitive firm profit:

$$
\pi=(P-ATC)q
$$

Short-run shutdown condition:

$$
P<\min AVC
$$

Long-run zero-profit condition:

$$
P=\min ATC
$$

Monopoly condition:

$$
MR=MC
$$

Monopoly markup rule:

$$
\frac{P-MC}{P}=-\frac{1}{\epsilon_d}
$$

Lerner index:

$$
L=\frac{P-MC}{P}
$$

Cournot firm \( i \):

$$
\pi_i=P(Q)q_i-C_i(q_i)
$$

Cournot first-order condition:

$$
P(Q)+q_iP'(Q)=MC_i(q_i)
$$

Herfindahl-Hirschman Index:

$$
HHI=\sum_i s_i^2
$$

## Game theory

Player \( i \)'s strategy:

$$
s_i \in S_i
$$

Expected payoff:

$$
EU_i=\sum_s p(s)u_i(s)
$$

Dominant strategy:

$$
u_i(s_i,s_{-i})\ge u_i(s_i',s_{-i})
\quad
\forall s_i',s_{-i}
$$

Nash equilibrium:

$$
s_i^* \in \arg\max_{s_i \in S_i} u_i(s_i,s_{-i}^*)
\quad
\forall i
$$

Prisoner's dilemma payoff order:

$$
T>R>P>S
$$

## Externalities and public goods

Efficient allocation:

$$
MSB=MSC
$$

Negative externality:

$$
MSC=MPC+MEC
$$

Positive externality:

$$
MSB=MPB+MEB
$$

Pigouvian tax:

$$
t^*=MEC(Q^*)
$$

Pigouvian subsidy:

$$
s^*=MEB(Q^*)
$$

Public good Samuelson condition:

$$
\sum_i MRS_i = MRT
$$

Common-resource efficient use:

$$
MB=MC+\text{external cost}
$$

## Information, risk, and intertemporal choice

Expected value:

$$
E[X]=\sum_i p_ix_i
$$

Expected utility:

$$
EU=\sum_i p_iu(x_i)
$$

Certainty equivalent:

$$
u(CE)=EU
$$

Risk premium:

$$
RP=E[X]-CE
$$

Fair insurance premium:

$$
\rho=pL
$$

Present value:

$$
PV=\sum_{t=0}^{T}\frac{C_t}{(1+r)^t}
$$

Two-period budget constraint:

$$
C_1+\frac{C_2}{1+r}
=
Y_1+\frac{Y_2}{1+r}
$$

Intertemporal optimum:

$$
MRS_{C_1C_2}=1+r
$$
