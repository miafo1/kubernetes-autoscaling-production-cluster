import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  stages: [
    { duration: '1m', target: 50 },  // Ramp up to 50 users
    { duration: '3m', target: 50 },  // Stay at 50 users (generating load)
    { duration: '1m', target: 0 },   // Ramp down
  ],
};

export default function () {
  // Replace with your ALB DNS Name
  // Can be passed via environment variable: k6 run -e ALB_DNS=...
  const url = `http://${__ENV.ALB_DNS}/load?duration=1`; 

  const res = http.get(url);

  check(res, {
    'status was 200': (r) => r.status === 200,
  });

  sleep(1);
}
