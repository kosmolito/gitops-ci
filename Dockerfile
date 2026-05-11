# Dockerfile
FROM nginx:alpine

COPY src/nginx.conf /etc/nginx/nginx.conf
COPY src/index.html /usr/share/nginx/html/index.html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]