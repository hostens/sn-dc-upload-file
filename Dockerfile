FROM alpine:3.10
RUN apk --no-cache add curl jq bash
RUN apk add --update coreutils
RUN apk upgrade apk-tools
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
