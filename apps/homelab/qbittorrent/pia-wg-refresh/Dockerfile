FROM alpine:3.24

RUN apk add --no-cache curl jq wireguard-tools

ARG KUBECTL_VERSION=v1.30.2
RUN wget -qO /usr/local/bin/kubectl \
      "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
 && chmod +x /usr/local/bin/kubectl

COPY regenerate.sh /usr/local/bin/regenerate.sh
RUN chmod +x /usr/local/bin/regenerate.sh

USER 65534:65534

ENTRYPOINT ["/usr/local/bin/regenerate.sh"]
