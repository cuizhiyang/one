#!/bin/bash
set -e

: ${NGX_PASS:="jiobxn.com"}
: ${NGX_CHARSET:="utf-8"}
: ${FCGI_PATH:="/var/www"}
: ${HTTP_PORT:="80"}
: ${HTTPS_PORT:="443"}
: ${ADDR_CACHE:="25m"}
: ${SSL_CACHE:="25m"}
: ${SSL_TIMEOUT:="10m"}
: ${DOMAIN_TAG:="888"}
: ${EOORO_JUMP:="https://cn.bing.com"}
: ${NGX_DNS="9.9.9.9"}
: ${CACHE_TIME:="10h"}
: ${CACHE_SIZE:="2g"}
: ${CACHE_MEM:="$(($(free -m |grep Mem |awk '{print $2}')*10/100))m"}
: ${KP_ETH:="$(route -n |awk '$1=="0.0.0.0"{print $NF}')"}
: ${KP_VRID:="77"}
: ${KP_PASS:="Newpa55"}
: ${WORKER_PROC:="2"}
: ${REMOTE_ADDR:="remote_addr"}
: ${COUNTRY_CODE:="CN"}



##-----------------HTTP----------------

http_conf() {
	echo "Initialize nginx"

	#global
	mkdir /nginx/conf/vhost
	cat >/nginx/conf/nginx.conf <<-END
	#redhat.xyz
	worker_processes  $WORKER_PROC;
	load_module modules/ngx_http_geoip2_module.so;

	events {
	    worker_connections  $(($WORKER_PROC*10240));
	}

	pid /tmp/nginx.pid;

	http {
	    include       mime.types;
	    default_type  application/octet-stream;

	    log_format  main  '\$remote_addr - \$remote_user [\$time_local] "\$request" '
	        '\$status \$body_bytes_sent "\$http_referer" '
	        '"\$http_user_agent" \$http_x_forwarded_for';
	    access_log  logs/access.log  main;
	    error_log   logs/error.log;

	    sendfile        on;
	    tcp_nopush      on;
	    keepalive_timeout  70;
	    server_names_hash_bucket_size 512;

	##acclog_off    access_log off;
	##errlog_off    error_log off;
		
	    charset $NGX_CHARSET;
	    client_max_body_size 0;
	    autoindex on;
	    server_tokens off;
		
	    proxy_cache_path /tmp/proxy_cache levels=1:2 keys_zone=cache1:$CACHE_MEM inactive=$CACHE_TIME max_size=$CACHE_SIZE;
	    fastcgi_cache_path /tmp/fastcgi_cache levels=1:2 keys_zone=cache2:$CACHE_MEM inactive=$CACHE_TIME max_size=$CACHE_SIZE;
		
	    gunzip on;
	    gzip  on;
	    gzip_comp_level 6;
	    gzip_proxied any;
	    gzip_types text/plain text/css text/xml text/javascript application/json application/x-javascript application/javascript application/xml application/xml+rss application/x-httpd-php image/jpeg image/gif image/png;
	    gzip_vary on;
		
	$GEOIP2    geoip2 /key/GeoLite2-Country.mmdb {
	$GEOIP2        \$geoip2_data_country_code default=$COUNTRY_CODE source=\$$REMOTE_ADDR country iso_code;
	$GEOIP2    }
		
	    #upstream#
		
	    include /nginx/conf/vhost/*.conf;
		
	##default_server    server {
	##default_server            listen       $HTTP_PORT  default_server;
	##default_server            listen       [::]:$HTTP_PORT  default_server;
	##default_server            server_name  _;
	##default_server            rewrite ^(.*) http://$DEFAULT_SERVER:$HTTP_PORT permanent;
	##default_server    }
	}
	daemon off;
	END


	#default
	cat >/nginx/conf/vhost/default.conf <<-END
	server {
	    listen       $HTTP_PORT;#
	    listen       $HTTPS_PORT ssl;
	    listen       [::]:$HTTP_PORT;#
	    listen       [::]:$HTTPS_PORT ssl;
	    server_name localhost;
		
	$GEOIP2    add_header "country" \$geoip2_data_country_code;
		
	    #LIMIT#
		
	    ssl_certificate      /nginx/conf/server.crt;
	    ssl_certificate_key  /nginx/conf/server.key;
	    ssl_session_cache shared:SSL:$SSL_CACHE;
	    ssl_session_timeout  $SSL_TIMEOUT;
	    ssl_protocols TLSv1 TLSv1.1 TLSv1.2 TLSv1.3;
	    ssl_ciphers  HIGH:!aNULL:!MD5;
	    ssl_prefer_server_ciphers   on;

	    location / {
	#   if (\$geoip2_data_country_code = CN) { root  /mnt; }
	        root   html;
	        index  index.html index.htm;
	    }

	##nginx_status    location ~ /basic_status {
	##nginx_status        stub_status;
	##nginx_status        auth_basic           "Nginx Stats";
	##nginx_status        auth_basic_user_file /nginx/.htpasswd;
	##nginx_status    }
	}
	END

	#限速,带单位
	if [ "$LIMIT_RATE" ]; then
		sed -i '/#LIMIT#/ a \    set $limit_rate '$LIMIT_RATE';' /nginx/conf/vhost/default.conf
	fi

	#最大并发数
	if [ "$LIMIT_CONN" ]; then
		sed -i '/#upstream#/ i \    limit_conn_zone $binary_remote_addr zone=addr:'$ADDR_CACHE';' /nginx/conf/nginx.conf
		sed -i '/#LIMIT#/ i \    limit_conn           addr '$LIMIT_CONN';' /nginx/conf/vhost/default.conf
		sed -i '/#LIMIT#/ i \    limit_conn_log_level error;' /nginx/conf/vhost/default.conf
		sed -i '/#LIMIT#/ i \    limit_conn_status    403;' /nginx/conf/vhost/default.conf
	fi

	#最大请求率
	if [ "$LIMIT_REQ" ]; then
		sed -i '/#upstream#/ i \    limit_req_zone $binary_remote_addr zone=one:'$ADDR_CACHE' rate='$LIMIT_REQ'r/s;' /nginx/conf/nginx.conf
		sed -i '/#LIMIT#/ i \    limit_req            zone=one burst='$LIMIT_REQ' nodelay;' /nginx/conf/vhost/default.conf
		sed -i '/#LIMIT#/ i \    limit_req_log_level  error;' /nginx/conf/vhost/default.conf
		sed -i '/#LIMIT#/ i \    limit_req_status     403;' /nginx/conf/vhost/default.conf
	fi
}



fcgi_server() {
	cat >/nginx/conf/vhost/fcgi_$n.conf <<-END
	server {
	    listen       $HTTP_PORT;#
	    listen       $HTTPS_PORT ssl;
	    listen       [::]:$HTTP_PORT;#
	    listen       [::]:$HTTPS_PORT ssl;
	    #server_name#

	##full_https    if (\$scheme = http) { return 301 https://\$host\$request_uri;}

	    ssl_certificate      /nginx/conf/server.crt;
	    ssl_certificate_key  /nginx/conf/server.key;
	    ssl_session_cache shared:SSL:$SSL_CACHE;
	    ssl_session_timeout  $SSL_TIMEOUT;
	    ssl_protocols TLSv1 TLSv1.1 TLSv1.2 TLSv1.3;
	    ssl_ciphers  HIGH:!aNULL:!MD5;
	    ssl_prefer_server_ciphers   on;

	    location / {
	        root   html;
	        index  index.php index.html index.htm;
	        try_files \$uri \$uri/ /index.php?q=\$uri&\$args;
	    }

	    #alias#

	    location ~ \.php$ {
	        fastcgi_pass   fcgi-lb-$n;
	        fastcgi_index  index.php;
	        fastcgi_param  SCRIPT_FILENAME  $FCGI_PATH\$fastcgi_script_name;
	        include        fastcgi_params;
	        fastcgi_read_timeout    300;
	        fastcgi_connect_timeout 300;
	        fastcgi_keep_conn on;
			
	##cache        fastcgi_cache cache1;
	##cache        fastcgi_cache_valid 200      $CACHE_TIME;
	##cache        fastcgi_cache_key \$host\$request_uri\$cookie_user\$scheme\$proxy_host\$uri\$is_args\$args;
	##cache        fastcgi_cache_use_stale  error timeout invalid_header updating http_500 http_502 http_503 http_504;

	##user_auth        auth_basic           "Nginx Auth";
	##user_auth        auth_basic_user_file /nginx/.htpasswd-tag;
	    }

	##nginx_status    location ~ /basic_status {
	##nginx_status        stub_status;
	##nginx_status        auth_basic           "Nginx Stats";
	##nginx_status        auth_basic_user_file /nginx/.htpasswd;
	##nginx_status    }

	    location ~ /\.ht {
	        deny  all;
	    }
	}
	END
}



java_php_server() {
	cat >/nginx/conf/vhost/java-php_$n.conf <<-END
	server {
	    listen       $HTTP_PORT;#
	    listen       $HTTPS_PORT ssl;
	    listen       [::]:$HTTP_PORT;#
	    listen       [::]:$HTTPS_PORT ssl;
	    #server_name#

	##full_https    if (\$scheme = http) { return 301 https://\$host\$request_uri;}

	    ssl_certificate      /nginx/conf/server.crt;
	    ssl_certificate_key  /nginx/conf/server.key;
	    ssl_session_cache shared:SSL:$SSL_CACHE;
	    ssl_session_timeout  $SSL_TIMEOUT;
	    ssl_protocols TLSv1 TLSv1.1 TLSv1.2 TLSv1.3;
	    ssl_ciphers  HIGH:!aNULL:!MD5;
	    ssl_prefer_server_ciphers   on;

	    location / {
	        root   html;
	        index  index.jsp index.php index.html index.htm;
	    }

	    #alias#

	    location ~ .(jsp|jspx|do|php)?$ {
	        proxy_pass http://java-php-lb-$n;
	        proxy_http_version 1.1;
	        proxy_read_timeout      300;
	        proxy_connect_timeout   300;
	        proxy_set_header   Connection "";
	        proxy_set_header   Host              \$host;
	        proxy_set_header   X-Real-IP         \$remote_addr;
	        proxy_set_header   X-Forwarded-Proto \$scheme;
	        proxy_set_header   X-Forwarded-For   \$proxy_add_x_forwarded_for;
	        proxy_set_header   Accept-Encoding  "";
			
	##cache        proxy_cache cache1;
	##cache        proxy_cache_valid 200      $CACHE_TIME;
	##cache        proxy_cache_key \$host\$request_uri\$cookie_user\$scheme\$proxy_host\$uri\$is_args\$args;
	##cache        proxy_cache_use_stale  error timeout invalid_header updating http_500 http_502 http_503 http_504;

	##user_auth        auth_basic           "Nginx Auth";
	##user_auth        auth_basic_user_file /nginx/.htpasswd-tag;
	    }

	##nginx_status    location ~ /basic_status {
	##nginx_status        stub_status;
	##nginx_status        auth_basic           "Nginx Stats";
	##nginx_status        auth_basic_user_file /nginx/.htpasswd;
	##nginx_status    }

	    location ~ /\.ht {
	        deny  all;
	    }
	}
	END
}



proxy_server() {
	cat >>/nginx/conf/vhost/proxy_$n.conf <<-END
	server {
	    listen       $HTTP_PORT;#
	    listen       $HTTPS_PORT ssl;
	    listen       [::]:$HTTP_PORT;#
	    listen       [::]:$HTTPS_PORT ssl;
	    #server_name#

	    ##full_https    if (\$scheme = http) { return 301 https://\$host\$request_uri;}

	    ssl_certificate      /nginx/conf/server.crt;
	    ssl_certificate_key  /nginx/conf/server.key;
	    ssl_session_cache shared:SSL:$SSL_CACHE;
	    ssl_session_timeout  $SSL_TIMEOUT;
	    ssl_protocols TLSv1 TLSv1.1 TLSv1.2 TLSv1.3;
	    ssl_ciphers  HIGH:!aNULL:!MD5;
	    ssl_prefer_server_ciphers   on;

	    #alias#

	    location / {
	        #PASS#
	        proxy_pass http://proxy-lb-$n;
	        proxy_http_version 1.1;
	        proxy_read_timeout      300;
	        proxy_connect_timeout   300;
	        proxy_set_header   Connection "";
	        proxy_set_header   Host              \$proxy_host;
	        proxy_set_header   X-Real-IP         \$remote_addr;
	        proxy_set_header   X-Forwarded-Proto \$scheme;
	        proxy_set_header   X-Forwarded-For   \$proxy_add_x_forwarded_for;
	        proxy_set_header   Accept-Encoding  "";
	        sub_filter_once    off;
	        sub_filter_types   * ;
			
	        #sub_filter#
	        sub_filter \$proxy_host \$host;
			
	##cache        proxy_cache cache1;
	##cache        proxy_cache_valid 200      $CACHE_TIME;
	##cache        proxy_cache_key \$host\$request_uri\$cookie_user\$scheme\$proxy_host\$uri\$is_args\$args;
	##cache        proxy_cache_use_stale  error timeout invalid_header updating http_500 http_502 http_503 http_504;
	
	##user_auth        auth_basic           "Nginx Auth";
	##user_auth        auth_basic_user_file /nginx/.htpasswd-tag;
	    }

	##nginx_status    location ~ /basic_status {
	##nginx_status        stub_status;
	##nginx_status        auth_basic           "Nginx Stats";
	##nginx_status        auth_basic_user_file /nginx/.htpasswd;
	##nginx_status    }

	    location ~ /\.ht {
	        deny  all;
	    }
	}
	END
}



domain_proxy() {
	cat >/nginx/conf/vhost/domain_$n.conf <<-END
	server {
	    listen       $HTTP_PORT;#
	    listen       $HTTPS_PORT ssl;
	    listen       [::]:$HTTP_PORT;#
	    listen       [::]:$HTTPS_PORT ssl;
	    #server_name#
	    server_name *.$(echo $i |awk -F^ '{print $1}'); #$(echo $i |awk -F^ '{print $1}')

	    ssl_certificate      /nginx/conf/server.crt;
	    ssl_certificate_key  /nginx/conf/server.key;
	    ssl_session_cache shared:SSL:$SSL_CACHE;
	    ssl_session_timeout  $SSL_TIMEOUT;
	    ssl_protocols TLSv1 TLSv1.1 TLSv1.2 TLSv1.3;
	    ssl_ciphers  HIGH:!aNULL:!MD5;
	    ssl_prefer_server_ciphers   on;
		
	    #rewrite#
	    #if (\$host !~* ^.*.$(echo $i |awk -F^ '{print $1}')$) {return 301 https://cn.bing.com;}
	    if (\$uri = /\$host) {rewrite ^(.*)$ https://\$host/index.php;}          #t66y login jump

	    set \$domain $(echo $i |awk -F^ '{print $1}');

	    location / {
            resolver $NGX_DNS;
            #domains#
            #if (\$host ~* "^(.*).$(echo $i |awk -F^ '{print $1}')$") {set \$domains \$1;}
            #if (\$host ~* "^(.*)-(.*).$(echo $i |awk -F^ '{print $1}')$" ) {set \$domains \$1.\$2;}
            if (\$host ~* "^(.*)$DOMAIN_TAG(.*).$(echo $i |awk -F^ '{print $1}')$" ) {set \$domains \$1\$2;}	#host rule
            if (\$domains = "t66y.com" ) {charset gb2312;}                                    					#t66y charset
            
            proxy_pass http://\$domains;
            proxy_http_version 1.1;
            proxy_read_timeout      300;
            proxy_connect_timeout   300;
            proxy_set_header   Connection "";
            proxy_set_header   Host              \$proxy_host;
            proxy_set_header   X-Real-IP         \$remote_addr;
            proxy_set_header   X-Forwarded-Proto \$scheme;
            proxy_set_header   X-Forwarded-For   \$proxy_add_x_forwarded_for;
            proxy_set_header   Accept-Encoding  "";
            sub_filter_once    off;
            sub_filter_types   * ;
			
            #sub_filter#
            sub_filter https:// \$scheme://;
            sub_filter .ytimg.com .yt${DOMAIN_TAG}img.com.\$domain;
            sub_filter .googlevideo.com .goog${DOMAIN_TAG}levideo.com.\$domain;
            sub_filter .ggpht.com .gg${DOMAIN_TAG}pht.com.\$domain;
            sub_filter .twimg.com .tw${DOMAIN_TAG}img.com.\$domain;
            sub_filter .fbcdn.net .fb${DOMAIN_TAG}cdn.net.\$domain;
            sub_filter .tumblr.com .tu${DOMAIN_TAG}mblr.com.\$domain;
	    sub_filter .youtube.com .you${DOMAIN_TAG}tube.com.\$domain;
	    sub_filter .google.com .go${DOMAIN_TAG}ogle.com.\$domain;
	    sub_filter .doubleclick.net .dou${DOMAIN_TAG}bleclick.net.\$domain;
	    sub_filter .amazonaws.com .amaz${DOMAIN_TAG}onaws.com.\$domain;
            sub_filter \$proxy_host \$host;
			
	##cache        proxy_cache cache1;
	##cache        proxy_cache_valid 200      $CACHE_TIME;
	##cache        proxy_cache_key \$host\$request_uri\$cookie_user\$scheme\$proxy_host\$uri\$is_args\$args;
	##cache        proxy_cache_use_stale  error timeout invalid_header updating http_500 http_502 http_503 http_504;
			
	##user_auth        auth_basic           "Nginx Auth";
	##user_auth        auth_basic_user_file /nginx/.htpasswd-tag;
	    }
		
	##nginx_status    location ~ /basic_status {
	##nginx_status        stub_status;
	##nginx_status        auth_basic           "Nginx Stats";
	##nginx_status        auth_basic_user_file /nginx/.htpasswd;
	##nginx_status    }
			
            error_page   500 502 503 504  /50x.html;
            location = /50x.html {return 301 https://cn.bing.com;}
	}
	END
}



http_other() {
	for i in $(echo $i |awk -F^ '{print $2}' |sed 's/,/\n/g'); do
		#WebSocket
		if [ -n "$(echo $i |grep 'ws=' |grep '|')" ]; then
			path="$(echo $i |awk -F= '{print$2}' |awk -F'|' '{print $1}')"
			ws="$(echo $i |awk -F= '{print$2}' |awk -F'|' '{print $2}')"
			
			sed -i '/#alias#/ a \    location '$path' {\n\        proxy_pass http://'$ws';\n\        proxy_http_version 1.1;\n\        proxy_set_header Upgrade \$http_upgrade;\n\        proxy_set_header Connection "upgrade";\n\    }\n' /nginx/conf/vhost/${project_name}_$n.conf 
		fi
		
		#WebSocket s
		if [ -n "$(echo $i |grep 'wss=' |grep '|')" ]; then
			path="$(echo $i |awk -F= '{print$2}' |awk -F'|' '{print $1}')"
			ws="$(echo $i |awk -F= '{print$2}' |awk -F'|' '{print $2}')"
			
			sed -i '/#alias#/ a \    location '$path' {\n\        proxy_pass https://'$ws';\n\        proxy_http_version 1.1;\n\        proxy_set_header Upgrade \$http_upgrade;\n\        proxy_set_header Connection "upgrade";\n\    }\n' /nginx/conf/vhost/${project_name}_$n.conf 
		fi
		
		#别名目录
		if [ -n "$(echo $i |grep 'alias=' |grep '|')" ]; then
			alias="$(echo $i |awk -F= '{print$2}' |awk -F'|' '{print $1}')"
			
			sed -i '/#alias#/ a \    location '$alias' {\n\        alias '$(echo $i |awk -F= '{print$2}' |awk -F'|' '{print $2}')';\n\    }\n' /nginx/conf/vhost/${project_name}_$n.conf 
		fi
		
		#网站根目录
		if [ -n "$(echo $i |grep 'root=')" ]; then
			root="$(echo $i |grep 'root=' |awk -F= '{print $2}')"
			
			sed -i 's@html;@html/'$root';@' /nginx/conf/vhost/${project_name}_$n.conf
			sed -i 's@$fastcgi_script_name@/'$root'$fastcgi_script_name@' /nginx/conf/vhost/${project_name}_$n.conf
		fi
		
		#HTTP端口
		if [ -n "$(echo $i |grep 'http_port=')" ]; then
			http="$(echo $i |grep 'http_port=' |awk -F= '{print $2}')"
			
			sed -i 's/'$HTTP_PORT';#/'$http';/' /nginx/conf/vhost/${project_name}_$n.conf
		fi
		
		#HTTPS端口
		if [ -n "$(echo $i |grep 'https_port=')" ]; then
			https="$(echo $i |grep 'https_port=' |awk -F= '{print $2}')"
			
			sed -i 's/'$HTTPS_PORT' ssl;/'$https' ssl;/' /nginx/conf/vhost/${project_name}_$n.conf
		fi
		
		#SSL证书
		if [ -n "$(echo $i |grep 'crt_key=' |grep '|')" ]; then
			crt="$(echo $i |grep 'crt_key=' |awk -F= '{print $2}' |awk -F'|' '{print $1}')"
			key="$(echo $i |grep 'crt_key=' |awk -F= '{print $2}' |awk -F'|' '{print $2}')"
			
			sed -i 's/server.crt;/'$crt';/' /nginx/conf/vhost/${project_name}_$n.conf
			sed -i 's/server.key;/'$key';/' /nginx/conf/vhost/${project_name}_$n.conf
		fi
		
		#HTTP2
		if [ -n "$(echo $i |grep 'http2=')" ]; then
			sed -i 's/ssl;/ssl http2;/' /nginx/conf/vhost/${project_name}_$n.conf
		fi
		
		#全站HTTPS
		if [ -n "$(echo $i |grep 'full_https=')" ]; then
			sed -i 's/##full_https//' /nginx/conf/vhost/${project_name}_$n.conf
		fi
		
		#字符集
		if [ -n "$(echo $i |grep 'charset=')" ]; then
			charset="$(echo $i |grep 'charset=' |awk -F= '{print $2}')"
			
			sed -i '/#alias#/ i \    charset '$charset';' /nginx/conf/vhost/${project_name}_$n.conf
		fi
		
		#启用缓存
		if [ -n "$(echo $i |grep 'cache=')" ]; then
			sed -i 's/##cache//g' /nginx/conf/vhost/${project_name}_$n.conf
		fi
		
		#上游主机头
		if [ -n "$(echo $i |grep 'header=')" ]; then
			header="$(echo $i |grep 'header=' |awk -F= '{print $2}')"
			
			sed -i 's/'$ngx_header';/'$header';/' /nginx/conf/vhost/${project_name}_$n.conf
		fi
		
		#负载均衡
		if [ -n "$(echo $i |grep 'http_lb=')" ]; then
			http_lb="$(echo $i |grep 'lb=' |awk -F= '{print $2}')"
		
			if [ "$http_lb" == "ip_hash" ]; then
				sed -i '/upstream '$project_name'-lb-'$n'/ a \        ip_hash;' /nginx/conf/nginx.conf
			fi
		
			if [ "$http_lb" == "hash" ]; then
				sed -i '/upstream '$project_name'-lb-'$n'/ a \        hash $remote_addr consistent;' /nginx/conf/nginx.conf
			fi
		
			if [ "$http_lb" == "least_conn" ]; then
				sed -i '/upstream '$project_name'-lb-'$n'/ a \        least_conn;' /nginx/conf/nginx.conf
			fi
		fi
		
		#上游HTTPS
		if [ -n "$(echo $i |grep 'backend_https=')" ]; then
			sed -i 's/proxy_pass http/proxy_pass https/g' /nginx/conf/vhost/${project_name}_$n.conf
		fi
		
		#DNS
		if [ -n "$(echo $i |grep 'dns=')" ]; then
			dns="$(echo $i |grep 'dns=' |awk -F= '{print $2}')"
			
			sed -i 's/'$NGX_DNS';/'$';/g' /nginx/conf/vhost/${project_name}_$n.conf
		fi
		
		#域名混淆字符
		if [ -n "$(echo $i |grep 'tag=')" ]; then
			tag="$(echo $i |grep 'tag=' |awk -F= '{print $2}')"
			
			sed -i 's/'$DOMAIN_TAG'/'$tag'/g' /nginx/conf/vhost/${project_name}_$n.conf
		fi
		
		#错误跳转
		if [ -n "$(echo $i |grep 'error=')" ]; then
			error="$(echo $i |grep 'error=' |awk -F= '{print $2}')"
			
			sed -i 's@'$EOORO_JUMP'@'$error'@' /nginx/conf/vhost/${project_name}_$n.conf
		fi
		
		#用户认证
		if [ -n "$(echo $i |grep 'auth=' |grep '|')" ]; then
			user="$(echo $i |grep 'auth=' |awk -F= '{print $2}' |awk -F'|' '{print $1}')"
			pass="$(echo $i |grep 'auth=' |awk -F= '{print $2}' |awk -F'|' '{print $2}')"
			
			echo "$user:$(openssl passwd -apr1 $pass)" > /nginx/.htpasswd-${project_name}_$n
			echo "Nginx user AND password: $user  $pass"
			
			sed -i 's/##user_auth//g' /nginx/conf/vhost/${project_name}_$n.conf
			sed -i 's/htpasswd-tag/htpasswd-'$project_name'_'$n'/' /nginx/conf/vhost/${project_name}_$n.conf
		fi
		
		#字符串替换
		if [ -n "$(echo $i |grep 'filter=' |grep '|')" ]; then
			for x in $(echo $i |grep 'filter=' |gawk -F= '{print $2}' |sed 's/&/\n/g'); do
				sub_s="$(echo $x |awk -F'|' '{print $1}')"
				sub_d="$(echo $x |awk -F'|' '{print $2}')"
				
				sed -i '/#sub_filter#/ a \        sub_filter '$sub_s'  '$sub_d';' /nginx/conf/vhost/${project_name}_$n.conf
			done
		fi

		#限速,带单位
		if [ -n "$(echo $i |grep 'limit_rate=')" ]; then
			limit_rate="$(echo $i |grep 'limit_rate=' |awk -F= '{print $2}')"
			
			sed -i '/#alias#/ i \    set $limit_rate '$limit_rate';' /nginx/conf/vhost/${project_name}_$n.conf
		fi

		#最大并发数
		if [ -n "$(echo $i |grep 'limit_conn=')" ]; then
			limit_conn="$(echo $i |grep 'limit_conn=' |awk -F= '{print $2}')"
		    
			sed -i '/#upstream#/ i \    limit_conn_zone  $binary_remote_addr zone=addr'$n':'$ADDR_CACHE';' /nginx/conf/nginx.conf
			sed -i '/#alias#/ i \        limit_conn_log_level error;' /nginx/conf/vhost/${project_name}_$n.conf
			sed -i '/#alias#/ i \        limit_conn_status    403;' /nginx/conf/vhost/${project_name}_$n.conf
			sed -i '/#alias#/ i \        limit_conn           addr'$n' '$limit_conn';' /nginx/conf/vhost/${project_name}_$n.conf
		fi

		#最大请求率
		if [ -n "$(echo $i |grep 'limit_req=')" ]; then
			limit_req="$(echo $i |grep 'limit_req=' |awk -F= '{print $2}')"
			
			sed -i '/#upstream#/ i \    limit_req_zone  $binary_remote_addr zone=one'$n':'$ADDR_CACHE' rate='$limit_req'r/s;' /nginx/conf/nginx.conf
			sed -i '/#alias#/ i \        limit_req_log_level  error;' /nginx/conf/vhost/${project_name}_$n.conf
			sed -i '/#alias#/ i \        limit_req_status     403;' /nginx/conf/vhost/${project_name}_$n.conf
			sed -i '/#alias#/ i \        limit_req            zone=one'$n' burst='$limit_req' nodelay;' /nginx/conf/vhost/${project_name}_$n.conf
		fi

		#日志
		if [ -n "$(echo $i |grep 'log=')" ]; then
			log="$(echo $i |grep 'log=' |awk -F= '{print $2}')"
			logfile="$(grep "server_name " /nginx/conf/vhost/${project_name}_$n.conf |awk -F# '{print $2}' |sort |head -1)"
			
			if [ "$log" == "Y" ]; then
				sed -i '/#server_name#/ i \    access_log logs\/'$logfile'-access.log main;' /nginx/conf/vhost/${project_name}_$n.conf
				sed -i '/#server_name#/ i \    error_log logs\/'$logfile'-error.log;' /nginx/conf/vhost/${project_name}_$n.conf
			fi
			
			if [ "$log" == "N" ]; then
				sed -i '/#server_name#/ i \    access_log off;' /nginx/conf/vhost/${project_name}_$n.conf
				sed -i '/#server_name#/ i \    error_log off;' /nginx/conf/vhost/${project_name}_$n.conf
			fi 
		fi
		
        #测试地址
        if [ -n "$(echo $i |grep 'testip=' |grep '&')" ]; then
                sip="$(echo $i |grep 'testip=' |awk -F= '{print $2}' |awk -F'&' '{print $1}')"
                dip="$(echo $i |grep 'testip=' |awk -F= '{print $2}' |awk -F'&' '{print $2}')"
		
                sed -i '/#PASS#/a \        if ($'$REMOTE_ADDR' ~ "'$sip'"){proxy_pass http://'$dip';break;}' /etc/nginx/conf.d/${project_name}_$n.conf
        fi
	done
}



http_basic() {
	if [ -n "$(echo $i |grep '^')" ]; then
		echo "^ yes"
		if [ -n "$(echo $i |awk -F^ '{print $1}' |grep '|')" ]; then
			for x in $(echo $i |awk -F^ '{print $1}' |awk -F'|' '{print $1}' |sed 's/,/\n/g'); do
				sed -i '/#server_name#/ a \    server_name '$x'; #'$x'' /nginx/conf/vhost/${project_name}_$n.conf
			done

			if [ -n "$(echo $i |awk -F^ '{print $1}' |awk -F'|' '{print $2}' |grep ",")" ]; then
				sed -i '/#upstream#/ a \    upstream '$project_name'-lb-'$n' {\n\        keepalive 20;\n\    }\n' /nginx/conf/nginx.conf

				for y in $(echo $i |awk -F^ '{print $1}' |awk -F'|' '{print $2}' |sed 's/,/\n/g'); do
					sed -i '/upstream '$project_name'-lb-'$n'/ a \        server '$y';' /nginx/conf/nginx.conf
				done
			else
				sed -i 's@'$project_name'-lb-'$n'@'$(echo $i |awk -F^ '{print $1}' |awk -F'|' '{print $2}')'@' /nginx/conf/vhost/${project_name}_$n.conf
			fi
		else
			sed -i '/#server_name#/ a \    server_name localhost; #localhost' /nginx/conf/vhost/${project_name}_$n.conf

			if [ -n "$(echo $i |awk -F^ '{print $1}' |grep ",")" ]; then
				sed -i '/#upstream#/a \    upstream '$project_name'-lb-'$n' {\n\        keepalive 20;\n\    }\n' /nginx/conf/nginx.conf

				for x in $(echo $i |awk -F^ '{print $1}' |sed 's/,/\n/g'); do
					sed -i '/upstream '$project_name'-lb-'$n'/ a \        server '$x';' /nginx/conf/nginx.conf
				done
			else
				sed -i 's@'$project_name'-lb-'$n'@'$(echo $i |awk -F^ '{print $1}')'@' /nginx/conf/vhost/${project_name}_$n.conf
			fi
		fi

		http_other
	else
		echo "^ no"
		if [ -n "$(echo $i |grep '|')" ]; then
			for x in $(echo $i |awk -F'|' '{print $1}' |sed 's/,/\n/g'); do
				sed -i '/#server_name#/ a \    server_name '$x'; #'$x'' /nginx/conf/vhost/${project_name}_$n.conf
			done

			if [ -n "$(echo $i |awk -F'|' '{print $2}' |grep ",")" ]; then
				sed -i '/#upstream#/ a \    upstream '$project_name'-lb-'$n' {\n\        keepalive 20;\n\    }\n' /nginx/conf/nginx.conf

				for y in $(echo $i |awk -F'|' '{print $2}' |sed 's/,/\n/g'); do
					sed -i '/upstream '$project_name'-lb-'$n'/ a \        server '$y';' /nginx/conf/nginx.conf
				done
			else
				sed -i 's@'$project_name'-lb-'$n'@'$(echo $i |awk -F'|' '{print $2}')'@' /nginx/conf/vhost/${project_name}_$n.conf
			fi
		else
			sed -i '/#server_name#/ a \    server_name localhost; #localhost' /nginx/conf/vhost/${project_name}_$n.conf

			if [ -n "$(echo $i |grep ",")" ]; then
				sed -i '/#upstream#/ a \    upstream '$project_name'-lb-'$n' {\n\        keepalive 20;\n\    }\n' /nginx/conf/nginx.conf

				for x in $(echo $i |sed 's/,/\n/g'); do
					sed -i '/upstream '$project_name'-lb-'$n'/ a \        server '$x';' /nginx/conf/nginx.conf
				done
			else
				sed -i 's@'$project_name'-lb-'$n'@'$i'@' /nginx/conf/vhost/${project_name}_$n.conf
			fi
		fi
	fi
}



##-------------------STREAM------------------

stream_conf() {
	cat >/nginx/conf/nginx.conf <<-END
	#redhat.xyz
	worker_processes  $WORKER_PROC;
	load_module modules/ngx_stream_geoip2_module.so;

	events {
	    worker_connections  $(($WORKER_PROC*10240));
	}

	stream {
	    log_format main '\$remote_addr:\$remote_port [\$time_local] \$protocol \$status \$session_time "\$upstream_addr" \$upstream_connect_time';
	    ##acclog_on access_log access.log main;
	    ##errlog_off error_log off;

	$GEOIP2    geoip2 /key/GeoLite2-Country.mmdb {
	$GEOIP2        \$geoip2_data_country_code default=$COUNTRY_CODE source=\$$REMOTE_ADDR country iso_code;
	$GEOIP2    }

	#example
	#    map \$$REMOTE_ADDR \$best_server {
	#        default all;
	#        1.2.3.4 test;
	#    }

	#    map \$geoip2_data_country_code \$best_server {
	#        default all;
	#        CN      cn;
	#    }

	#    upstream all {
	#        server 172.17.0.1:1808;
	#    }

	#    upstream cn {
	#        server 172.17.0.1:1809;
	#    }

	#    server {
	#        listen 80;
	#        proxy_pass \$best_server;
	#    }

	    #upstream#

	    #server#
	}
	daemon off;
	END
}



stream_server() {
	if [ -n "$(echo $i |grep '^')" ]; then
		echo "^ yes"
		if [ -n "$(echo $i |awk -F^ '{print $1}' |grep '|')" ]; then
			PORT=$(echo $i |awk -F^ '{print $1}' |awk -F'|' '{print $1}')

			if [ -n "$(echo $i |awk -F^ '{print $1}' |awk -F'|' '{print $2}' |grep ",")" ]; then
				sed -i '/#upstream#/ a \    upstream backend-lb-'$n' {\n\    }\n' /nginx/conf/nginx.conf

				for y in $(echo $i |awk -F^ '{print $1}' |awk -F'|' '{print $2}' |sed 's/,/\n/g'); do
					sed -i '/upstream backend-lb-'$n'/ a \        server '$y';' /nginx/conf/nginx.conf
					sed -i 's/&/ /' /nginx/conf/nginx.conf
				done
				
				sed -i '/#server#/ a \    server {\n\        #backend-lb-'$n'#\n\        listen '$PORT';\n\        listen [::]:'$PORT';#'$n'\n\        proxy_pass backend-lb-'$n';\n\    }\n' /nginx/conf/nginx.conf
			else
				sed -i '/#server#/ a \    server {\n\        #backend-lb-'$n'#\n\        listen '$PORT';\n\        listen [::]:'$PORT';#'$n'\n\        proxy_pass '$(echo $i |awk -F^ '{print $1}' |awk -F'|' '{print $2}')';\n\    }\n' /nginx/conf/nginx.conf
			fi
		else
			echo "error.." && exit 1
		fi
	else
		echo "^ no"
		if [ -n "$(echo $i |grep '|')" ]; then
			PORT=$(echo $i |awk -F'|' '{print $1}')

			if [ -n "$(echo $i |awk -F'|' '{print $2}' |grep ",")" ]; then
				sed -i '/#upstream#/ a \    upstream backend-lb-'$n' {\n\    }\n' /nginx/conf/nginx.conf

				for y in $(echo $i |awk -F'|' '{print $2}' |sed 's/,/\n/g'); do
					sed -i '/upstream backend-lb-'$n'/ a \        server '$y';' /nginx/conf/nginx.conf
					sed -i 's/&/ /' /nginx/conf/nginx.conf
				done
				
				sed -i '/#server#/ a \    server {\n\        #backend-lb-'$n'#\n\        listen '$PORT';\n\        listen [::]:'$PORT';#'$n'\n\        proxy_pass backend-lb-'$n';\n\    }\n' /nginx/conf/nginx.conf
			else
				sed -i '/#server#/ a \    server {\n\        #backend-lb-'$n'#\n\        listen '$PORT';\n\        listen [::]:'$PORT';#'$n'\n\        proxy_pass '$(echo $i |awk -F'|' '{print $2}')';\n\    }\n' /nginx/conf/nginx.conf
			fi
		else
			echo "error.." && exit 1
		fi
	fi
}
	


stream_other() {
	for i in $(echo $i |awk -F^ '{print $2}' |sed 's/,/\n/g'); do		
		#负载均衡
		if [ -n "$(echo $i |grep 'stream_lb=')" ]; then
			stream_lb="$(echo $i |grep 'stream_lb=' |awk -F= '{print $2}')"
		
			if [ "$stream_lb" == "hash" ]; then
				sed -i '/upstream backend-lb-'$n'/ a \        hash $remote_addr consistent;' /nginx/conf/nginx.conf
			fi
			
			if [ "$stream_lb" == "least_conn" ]; then
				sed -i '/upstream backend-lb-'$n'/ a \        least_conn;' /nginx/conf/nginx.conf
			fi
		fi
		
		#后端连接超时(1m)
		if [ -n "$(echo $i |grep 'conn_timeout=')" ]; then
			connect_timeout="$(echo $i |grep 'connect_timeout=' |awk -F= '{print $2}')"
			sed -i '/#backend-lb-'$n'#/ a \        proxy_connect_timeout '$connect_timeout';' /nginx/conf/nginx.conf
		fi
		
		#空闲超时(10m)
		if [ -n "$(echo $i |grep 'proxy_timeout=')" ]; then
			proxy_timeout="$(echo $i |grep 'proxy_timeout=' |awk -F= '{print $2}')"
			sed -i '/#backend-lb-'$n'#/ a \        proxy_timeout '$proxy_timeout';' /nginx/conf/nginx.conf
		fi
		
		#UDP, 不能和SSL共存
		if [ -n "$(echo $i |grep 'udp=')" ]; then
			sed -i 's/'$PORT';#'$n'/'$PORT' udp;#'$n'/' /nginx/conf/nginx.conf
		fi
		
		#最大并发数
		if [ -n "$(echo $i |grep 'limit_conn=')" ]; then
		    limit_conn="$(echo $i |grep 'limit_conn=' |awk -F= '{print $2}')"
			sed -i '/#upstream#/ i \    limit_conn_zone $binary_remote_addr zone=addr'$n':'$ADDR_CACHE';' /nginx/conf/nginx.conf
			sed -i '/#backend-lb-'$n'#/ a \        limit_conn_log_level error;' /nginx/conf/nginx.conf
			sed -i '/#backend-lb-'$n'#/ a \        limit_conn           addr'$n' '$limit_conn';' /nginx/conf/nginx.conf
		fi
		
		#SSL
		if [ -n "$(echo $i |grep 'ssl=')" ]; then
			sed -i 's/'$PORT';#'$n'/'$PORT' ssl;#'$n'/' /nginx/conf/nginx.conf
			sed -i '/#backend-lb-'$n'#/ a \        ssl_certificate_key     /nginx/conf/server.key;' /nginx/conf/nginx.conf
			sed -i '/#backend-lb-'$n'#/ a \        ssl_certificate         /nginx/conf/server.crt;' /nginx/conf/nginx.conf
			sed -i '/#backend-lb-'$n'#/ a \        ssl_session_timeout '$SSL_TIMEOUT';' /nginx/conf/nginx.conf
			sed -i '/#backend-lb-'$n'#/ a \        ssl_session_cache   shared:SSL:'$SSL_CACHE';' /nginx/conf/nginx.conf
			sed -i '/#backend-lb-'$n'#/ a \        ssl_ciphers         AES128-SHA:AES256-SHA:RC4-SHA:DES-CBC3-SHA:RC4-MD5;' /nginx/conf/nginx.conf
			sed -i '/#backend-lb-'$n'#/ a \        ssl_protocols       TLSv1 TLSv1.1 TLSv1.2 TLSv1.3;' /nginx/conf/nginx.conf
		fi
		
		#上游SSL
		if [ -n "$(echo $i |grep 'ssl_backend=')" ]; then
			sed -i '/#backend-lb-'$n'#/ a \        proxy_ssl_certificate_key     /nginx/conf/server.key;' /nginx/conf/nginx.conf
			sed -i '/#backend-lb-'$n'#/ a \        proxy_ssl_certificate         /nginx/conf/server.crt;' /nginx/conf/nginx.conf
			sed -i '/#backend-lb-'$n'#/ a \        proxy_ssl  on;' /nginx/conf/nginx.conf
		fi
		
		#日志
		if [ -n "$(echo $i |grep 'log=')" ]; then
			log="$(echo $i |grep 'log=' |awk -F= '{print $2}')"
			
			if [ "$log" == "Y" ]; then
				sed -i '/#backend-lb-'$n'#/ a \        access_log logs\/'$n'-access.log main;' /nginx/conf/nginx.conf
				sed -i '/#backend-lb-'$n'#/ a \        error_log logs\/'$n'-error.log;' /nginx/conf/nginx.conf
			fi
			
			if [ "$log" == "N" ]; then
				sed -i '/#backend-lb-'$n'#/ i \        access_log off;' /nginx/conf/nginx.conf
				sed -i '/#backend-lb-'$n'#/ i \        error_log off;' /nginx/conf/nginx.conf
			fi 
		fi
		
                #访问控制
                if [ -n "$(echo $i |grep 'allow=')" ]; then
                        sed -i '/#backend-lb-'$n'#/ a \        deny  all;' /etc/nginx/nginx.conf
                        for x in $(echo $i |grep 'allow=' |gawk -F= '{print $2}' |sed 's/&/\n/g'); do
                                sed -i '/#backend-lb-'$n'#/ a \        allow '$x';' /etc/nginx/nginx.conf
                        done
                fi
	done
}




###start

if [ "$1" = 'nginx' ]; then
  if [ -z "$(grep "redhat.xyz" /nginx/conf/nginx.conf)" ]; then
	if [ -f /key/server.crt -a -f /key/server.key ]; then
		\cp /key/*.{crt,key} /nginx/conf/
	else
		openssl genrsa -out /nginx/conf/server.key 4096 2>/dev/null
		openssl req -new -key /nginx/conf/server.key -out /nginx/conf/server.csr -subj "/C=CN/L=London/O=Company Ltd/CN=nginx-docker" 2>/dev/null
		openssl x509 -req -days 3650 -in /nginx/conf/server.csr -signkey /nginx/conf/server.key -out /nginx/conf/server.crt 2>/dev/null
                \cp /nginx/conf/server.{crt,key} /key/
	fi


	if [ -f /key/GeoLite2-Country.mmdb ]; then
		\cp /key/GeoLite2-Country.mmdb /nginx/conf/
	else
		GEOIP2="##"
	fi


	if [ "$STREAM_SERVER" ]; then
		stream_conf
		
		n=0
		for i in $(echo "$STREAM_SERVER" |sed 's/;/\n/g'); do
			n=$(($n+1))
			stream_server
			stream_other
		done

		if [ "$ACCLOG_ON" ]; then
			sed -i 's/##acclog_on//' /nginx/conf/nginx.conf
		fi

		if [ "$ERRLOG_OFF" ]; then
			sed -i 's/##errlog_off//' /nginx/conf/nginx.conf
		fi
	else
	
		http_conf

		#FCGI
		if [ "$FCGI_SERVER" ]; then
			n=0
			for i in $(echo "$FCGI_SERVER" |sed 's/;/\n/g'); do
				n=$(($n+1))
				fcgi_server
				project_name="fcgi"
				ngx_header="host"
				http_basic
			done
			\mv /nginx/conf/vhost/default.conf /nginx/conf/vhost/default.txt
		fi


		#JAVA_PHP
		if [ "$JAVA_PHP_SERVER" ]; then
			n=0
			for i in $(echo "$JAVA_PHP_SERVER" |sed 's/;/\n/g'); do
				n=$(($n+1))
				java_php_server
				project_name="java-php"
				ngx_header="host"
				http_basic
			done
			\mv /nginx/conf/vhost/default.conf /nginx/conf/vhost/default.txt 2>/dev/null |echo
		fi


		#PROXY
		if [ "$PROXY_SERVER" ]; then
			n=0
			for i in $(echo "$PROXY_SERVER" |sed 's/;/\n/g'); do
				n=$(($n+1))
				proxy_server
				project_name="proxy"
				ngx_header="proxy_host"
				http_basic
			done
			\mv /nginx/conf/vhost/default.conf /nginx/conf/vhost/default.txt 2>/dev/null |echo
		fi


		#DOMAIN
		if [ "$DOMAIN_PROXY" ]; then
			n=0
			for i in $(echo "$DOMAIN_PROXY" |sed 's/;/\n/g'); do
				n=$(($n+1))
				domain_proxy
				project_name="domain"
				ngx_header="proxy_host"
				http_other
			done
			\mv /nginx/conf/vhost/default.conf /nginx/conf/vhost/default.txt 2>/dev/null |echo
		fi


		if [ "$ACCLOG_OFF" ]; then
			sed -i 's/##acclog_off//' /nginx/conf/nginx.conf
		fi

		if [ "$ERRLOG_OFF" ]; then
			sed -i 's/##errlog_off//' /nginx/conf/nginx.conf
		fi

		if [ "$DEFAULT_SERVER" ]; then
			sed -i 's/##default_server//g' /nginx/conf/vhost/*.conf
		fi

		if [ "$NGX_USER" ]; then
			sed -i 's/##nginx_status//g' /nginx/conf/vhost/default.conf
			echo "$NGX_USER:$(openssl passwd -apr1 $NGX_PASS)" >> /nginx/.htpasswd
			echo "Nginx user AND password: $NGX_USER  $NGX_PASS"
		fi
	fi

	#keepalived
	\rm /etc/keepalived/keepalived.conf
	if [ $KP_VIP ]; then
		cat >/etc/keepalived/keepalived.conf <<-END
		! Configuration File for keepalived
		
		vrrp_instance VI_1 {
		    state BACKUP
		    interface $KP_ETH
		    virtual_router_id $KP_VRID
		    priority 100
		    advert_int 1

		    authentication {
		        auth_type PASS
		        auth_pass $KP_PASS
		    }

		    virtual_ipaddress {
		    }
		}
		END
		
		for vip in $(echo $KP_VIP |sed 's/,/ /g');do
			sed -i "/virtual_ipaddress/a \        $vip" /etc/keepalived/keepalived.conf
		done
	fi
	
  fi

	echo "Start ****"
	#Keepalived Need root authority "--privileged"
	[ -f /etc/keepalived/keepalived.conf ] && keepalived -f /etc/keepalived/keepalived.conf -P -l && [ -z "`iptables -S |grep vrrp`" ] && iptables -I INPUT -p vrrp -j ACCEPT

	exec "$@"
else

	echo -e " 
	Example:
				docker run -d --restart unless-stopped [--cap-add NET_ADMIN] \\
				-v /docker/www:/nginx/html \\
				-v /docker/upload:/mp4 \\
				-v /docker/key:/key \\
				-p 10080:80 \\
				-p 10443:443 \\
				-e WORKER_PROC=[2] \\
				-e FCGI_SERVER=<php.jiobxn.com|192.17.0.5:9000[^<Other options>]> \\
				-e JAVA_PHP_SERVER=<tomcat.jiobxn.com|192.17.0.6:8080[^<Other options>];apache.jiobxn.com|192.17.0.7[^<Other options>]> \\
				-e PROXY_SERVER=<g.jiobxn.com|www.google.co.id^backend_https=Y> \\
				-e DOMAIN_PROXY=<fqhub.com^backend_https=Y> \\
				-e DEFAULT_SERVER=<jiobxn.com> \\
				-e NGX_PASS=[jiobxn.com] \\
				-e NGX_USER=<nginx> \\
				-e NGX_CHARSET=[utf-8] \\
				-e FCGI_PATH=[/var/www] \\
				-e HTTP_PORT=[80] \\
				-e HTTPS_PORT=[443] \\
				-e ADDR_CACHE=[25m] \\
				-e SSL_CACHE=[25m] \\
				-e SSL_TIMEOUT=[10m] \\
				-e DOMAIN_TAG=[888] \\
				-e EOORO_JUMP=[https://cn.bing.com] \\
				-e NGX_DNS=[9.9.9.9] \\
				-e CACHE_TIME=[10h] \\
				-e CACHE_SIZE=[2g] \\
				-e CACHE_MEM=[256m] \\
				-e ACCLOG_OFF=<Y> \\
				-e ERRLOG_OFF=<Y> \\
				-e ACCLOG_ON=<Y> \\
				-e LIMIT_RATE=<2048k> \\
				-e LIMIT_CONN=<50> \\
				-e LIMIT_REQ=<2> \\
				-e REMOTE_ADDR=[remote_addr] \\
				-e COUNTRY_CODE=[CN] \\
				-e ws=</mp4|127.0.0.1:19443> \\
				   wss=</mp4|127.0.0.1:19444> \\
				   alias=</boy|/mp4> \\
				   root=<wordpress> \\
				   http_port=<8080> \\
				   https_port=<8443> \\
				   crt_key=<jiobxn.crt|jiobxn.key> \\
				   full_https=<Y> \\
				   http2=<Y> \\
				   charset=<gb2312> \\
				   cache=<Y> \\
				   header=<host|http_host|proxy_host> \\
				   http_lb=<ip_hash|hash|least_conn> \\
				   backend_https=<Y> \\
				   dns=<223.5.5.5> \\
				   tag=<9999> \\
				   error=<https://www.bing.com> \\
				   auth=<admin|passwd> \\
				   filter=<.google.com|.fqhub.com&.twitter.com|.fqhub.com> \\
				   limit_rate=<2048k> \\
				   limit_conn=<50> \\
				   limit_req=<2> \\
				   log=<N|Y> \\
				   testip=<1.1.1.1&10.0.0.10:8080> \\
				-e STREAM_SERVER=<3306|192.17.0.7:3306&backup,192.17.0.6:3306[^<Other options>];53|8.8.8.8:53^udp=Y> \\
				   stream_lb=<hash|least_conn> \\
				   conn_timeout=[1m] \\
				   proxy_timeout=[10m] \\
				   limit_conn=<50> \\
				   udp=<Y> \\
				   log=<N|Y> \\
				   ssl=<Y> \\
				   ssl_backend=<Y> \\
				   allow=<1.2.3.4&5.6.7.8> \\
				-e KP_VIP=<20.20.6.4,20.20.6.25> \\
				-e KP_ETH=[default interface] \\
				-e KP_VRID=[77] \\
				-e KP_PASS=[Newpa55] \\
				--name nginx nginx
	" 
fi
