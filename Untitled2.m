pf=makedist('InverseGaussian','mu',1,'lambda',1);%establish whatever you want for mu and lambda
x=0:.001:2;%establish whatever values you want evaluated
y=pdf(pf,x);
plot(x,y);