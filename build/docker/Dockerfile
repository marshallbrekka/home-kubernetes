FROM debian:stretch

# p7zip-full: for expanding the 7z os download files
# curl: downloading files
# make: you know, for making things... :P
# jq: accessing json output, in this case disk partition info from sfdisk
# whois: provides mkpasswd
RUN apt-get update && apt-get install --yes \
    p7zip-full \
    curl \
    make \
    jq \
    whois
