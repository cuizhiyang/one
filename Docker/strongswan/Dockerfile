FROM centos:latest
MAINTAINER The CentOS Project <admin@jiobxn.com>

RUN \cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
RUN epel_url="http://dl.fedoraproject.org/pub/epel/$(awk '{print $4}' /etc/redhat-release |awk -F. '{print $1}')/x86_64/e/" \
        && rpm -ivh $epel_url$(curl -s $epel_url |grep "epel-release" |awk -F\" '{print $6}')
RUN yum clean all; yum -y update; yum -y install strongswan xl2tpd openssl iptables cronie net-tools bash-completion vim; yum clean all

VOLUME /key

COPY strongswan.sh /strongswan.sh
RUN chmod +x /strongswan.sh

WORKDIR /usr/sbin

ENTRYPOINT ["/strongswan.sh"]

EXPOSE 500/udp 4500/udp 1701/udp

CMD ["strongswan", "start", "--nofork"]

# docker build -t strongswan .
# docker run -d --restart always --privileged -v /docker/strongswan:/key --network=host -e VPN_PASS=123456 --hostname strongswan --name strongswan strongswan
# cat /docker/strongswan/strongswan.log