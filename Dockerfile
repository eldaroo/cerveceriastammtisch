FROM wordpress:php8.2-apache

COPY public/ /usr/src/wordpress/

RUN rm -f /usr/src/wordpress/wp-config.php \
  && rm -rf /usr/src/wordpress/wp-content/updraft \
  && chown -R www-data:www-data /usr/src/wordpress
