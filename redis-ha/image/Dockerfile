FROM alpine:3.6
RUN apk add --no-cache 'su-exec>=0.2' sed bash ruby

ENV REDIS_VERSION 4.0.8
ENV REDIS_DOWNLOAD_URL http://download.redis.io/releases/redis-${REDIS_VERSION}.tar.gz
ENV TIME_ZONE Asiz/Shanghai

RUN set -ex; \
  apk update && apk add --no-cache --virtual .build-deps \
		coreutils \
		gcc \
		linux-headers \
		make \
		musl-dev \
		tzdata \
		tree \
		curl \
		jq; \
  cp -r -f /usr/share/zoneinfo/Hongkong /etc/localtime ; \
    echo -ne "Alpine Linux 3.6 image. (`uname -rsv`)\n" >> /root/.built ;\
	wget -O redis.tar.gz "$REDIS_DOWNLOAD_URL"; \
	mkdir -p /usr/src/redis; \
	tar -xzf redis.tar.gz -C /usr/src/redis --strip-components=1; \
	rm redis.tar.gz; \
	grep -q '^#define CONFIG_DEFAULT_PROTECTED_MODE 1$' /usr/src/redis/src/server.h; \
	sed -ri 's!^(#define CONFIG_DEFAULT_PROTECTED_MODE) 1$!\1 0!' /usr/src/redis/src/server.h; \
	grep -q '^#define CONFIG_DEFAULT_PROTECTED_MODE 0$' /usr/src/redis/src/server.h; \
	make -C /usr/src/redis -j "$(nproc)"; \
	make -C /usr/src/redis install; \
	mkdir -p /code/redis ;\
	rm -r /usr/src/redis; \
  apk del .build-deps ; \
	apk add --no-cache curl jq

RUN gem sources --add https://gems.ruby-china.org/ --remove https://rubygems.org/;

EXPOSE 6379
EXPOSE 6380
EXPOSE 26379

COPY redis-master.conf /config/redis/master.conf
COPY redis-slave.conf /config/redis/slave.conf
COPY redis-cluster.conf /config/redis/cluster.conf
RUN touch /config/redis/sentinel.conf
COPY entrypoint.sh /code/redis/entrypoint.sh
COPY redis-4.0.1.gem /redis-401.gem
COPY rdoc-6.0.0.gem /rdoc-600.gem
COPY redis-trib.rb /code/redis/redis-trib.rb

RUN chmod +x /code/redis/entrypoint.sh ;\
	chmod +x /code/redis/redis-trib.rb

CMD [ "/code/redis/entrypoint.sh" ]
ENTRYPOINT [ "bash", "-c" ]
