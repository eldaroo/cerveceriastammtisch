FROM wordpress:php8.2-apache

COPY public/ /var/www/html/

RUN rm -f /var/www/html/wp-config.php \
  && rm -rf /var/www/html/wp-content/updraft \
  && chown -R www-data:www-data /var/www/html
