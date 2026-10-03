import http from 'k6/http';
import { check } from 'k6';

// E3 capacity test (PLAN.md §9, M12). Raises the arrival rate step by step
// until the API stops meeting its latency SLO or starts failing, then stops.
// Run it through scripts/waf-benchmark-window.sh, never on its own: from one
// IP, the WAF's rate limit (2,000 requests per 5 minutes) blocks it within
// seconds otherwise.
//
// An arrival-rate executor holds the request rate fixed regardless of how
// slowly the API answers, so a slow API shows up as latency instead of quietly
// lowering the load. If k6 cannot keep up, it reports dropped_iterations:
// then the generator, not the API, set the limit.

const TARGET_URL = __ENV.TARGET_URL;
const START_RATE = Number(__ENV.START_RATE || 10); // requests per second
const MAX_RATE = Number(__ENV.MAX_RATE || 400);
const STEPS = Number(__ENV.STEPS || 8);
const STEP_DURATION = __ENV.STEP_DURATION || '2m';

const stages = [];
for (let i = 1; i <= STEPS; i++) {
  const rate = Math.round(START_RATE + ((MAX_RATE - START_RATE) * i) / STEPS);
  stages.push({ target: rate, duration: '30s' }); // ramp to the step
  stages.push({ target: rate, duration: STEP_DURATION }); // hold it
}

export const options = {
  scenarios: {
    ramp: {
      executor: 'ramping-arrival-rate',
      startRate: START_RATE,
      timeUnit: '1s',
      preAllocatedVUs: 50,
      maxVUs: 500,
      stages,
    },
  },
  thresholds: {
    // The latency SLO (docs/observability/slo.md) and a 1% error ceiling.
    // abortOnFail ends the run at the first sustained breach; the rate at
    // that moment, read from the per-request CSV, is the saturation point.
    http_req_duration: [{ threshold: 'p(95)<500', abortOnFail: true, delayAbortEval: '30s' }],
    http_req_failed: [{ threshold: 'rate<0.01', abortOnFail: true, delayAbortEval: '30s' }],
  },
};

export default function () {
  // The cache-aside read path (Redis, then Postgres on a miss): the API's
  // most common request.
  const res = http.get(`${TARGET_URL}/api/products`, { tags: { name: 'list-products' } });
  check(res, { 'status is 200': (r) => r.status === 200 });
}
