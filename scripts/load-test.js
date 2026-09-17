import http from 'k6/http';
import { check } from 'k6';

const TARGET_URL = __ENV.TARGET_URL;
const HEADER_NAME = __ENV.ORIGIN_SECRET_HEADER_NAME;
const HEADER_VALUE = __ENV.ORIGIN_SECRET_HEADER_VALUE;

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
  const res = http.get(`${TARGET_URL}/readyz`, {
    headers: { [HEADER_NAME]: HEADER_VALUE },
  });

  check(res, { 'status is 200': (r) => r.status === 200 });
}
