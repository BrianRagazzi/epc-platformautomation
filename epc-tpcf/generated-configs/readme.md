

om --env env.yml products

om --env env.yml staged-config
   --product-name "$PRODUCT_NAME" \
   --include-credentials >  ./generated-config/"$PRODUCT_NAME".yml
