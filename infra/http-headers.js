'use strict';

exports.handler = (event, context, callback) => {
    const add = (h, k, v) => {
        h[k.toLowerCase()] = [
            {
                key: k,
                value: v
            }
        ];
    };

    const response = event.Records[0].cf.response;
    const headers = response.headers;

    add(headers, "Strict-Transport-Security", "max-age=31536000; includeSubDomains; preload");
    add(headers, "X-Content-Type-Options", "nosniff");
    add(headers, "X-XSS-Protection", "1; mode=block");
    add(headers, "X-Frame-Options", "DENY");
    add(headers, "Referrer-Policy", "no-referrer-when-downgrade");
    callback(null, response);
};

// Uncomment below to test
/*
exports.handler({
  "Records": [
    {
      "cf": {
        "config": {
          "distributionId": "EXAMPLE"
        },
        "response": {
          "status": "200",
          "statusDescription": "OK",
          "headers": {
            "vary": [
              {
                "key": "Vary",
                "value": "*"
              }
            ],
            "last-modified": [
              {
                "key": "Last-Modified",
                "value": "2016-11-25"
              }
            ],
            "x-amz-meta-last-modified": [
              {
                "key": "X-Amz-Meta-Last-Modified",
                "value": "2016-01-01"
              }
            ]
          }
        }
      }
    }
  ]
}, {}, (_, __) => {});
*/
