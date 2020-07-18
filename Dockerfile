FROM centos:7

RUN yum -y update
RUN yum -y install nfs-utils nfs-utils-lib
RUN yum -y install samba samba-client cifs-utils
RUN yum -y install net-tools

ADD ./entrypoint.sh ./entrypoint.sh
ARG MOUNT_COMMAND
ARG MOUNT_TARGET
ENTRYPOINT ["./entrypoint.sh", "${MOUNT_COMMAND}", "${MOUNT_TARGET}"]
