FROM jenkins/jenkins
MAINTAINER chandu
USER root
RUN apt-get update
RUN apt-get install -y maven git
WORKDIR /root
USER jenkins


