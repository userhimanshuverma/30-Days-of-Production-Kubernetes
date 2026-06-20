import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  stages: [
    { duration: '30s', target: 50 },  // Ramp up to 50 virtual users
    { duration: '1m', target: 50 },   // Hold load at 50 users
    { duration: '15s', target: 0 },   // Cool down to 0 users
  ],
  thresholds: {
    http_req_failed: ['rate<0.02'],   // Under 2% failure rate allowed
    http_req_duration: ['p(95)<500'], // 95% of requests must resolve under 500ms
  },
};

export default function () {
  const url = 'http://ai.platform.company.com/predict';
  const payload = JSON.stringify({
    data: [
      Math.random() * 10,
      Math.random() * 10,
      Math.random() * 10
    ]
  });

  const params = {
    headers: {
      'Content-Type': 'application/json',
    },
  };

  const res = http.post(url, payload, params);

  check(res, {
    'status is 200': (r) => r.status === 200,
    'prediction key exists': (r) => {
      try {
        const body = JSON.parse(r.body);
        return body && body.hasOwnProperty('prediction');
      } catch (e) {
        return false;
      }
    },
  });

  // Small delay between requests to simulate user behavior
  sleep(0.1);
}
