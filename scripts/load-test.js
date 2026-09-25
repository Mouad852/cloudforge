import http from 'k6/http';
import { check, sleep } from 'k6';

const TARGET_URL = __ENV.TARGET_URL;

export const options = {
  vus: 5,
  duration: __ENV.K6_DURATION || '8m',
  thresholds: {
    // Any failed request fails the whole run - this is the deploy gate,
    // not just an observation: a rollout with the health-check timing
    // wrong shows up here as dropped requests, not just in server logs.
    http_req_failed: ['rate==0'],
  },
};

export default function () {
  const res = http.get(`${TARGET_URL}/readyz`);

  check(res, { 'status is 200': (r) => r.status === 200 });

  // About 1 request/s per VU: 5 VUs send ~1,500 requests per 5 minutes, under
  // the WAF's 2,000-per-5-minutes-per-IP rate limit (ADR-025). With no pause,
  // 5 VUs send ~34/s from one runner IP, and the WAF blocks the deploy gate
  // itself within about a minute.
  sleep(1);
}
