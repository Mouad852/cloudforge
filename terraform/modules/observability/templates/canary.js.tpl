const synthetics = require('@aws/synthetics-puppeteer');
const log = require('@aws/synthetics-logger');

const apiCanaryBlueprint = async function () {
  const url = "${target_url}";

  const page = await synthetics.getPage();
  const response = await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 30000 });

  if (!response) {
    throw new Error('No response returned for ' + url);
  }

  const status = response.status();
  if (status < 200 || status > 299) {
    throw new Error('Failed to load url: ' + url + ' status: ' + status);
  }

  log.info('Response status: ' + status);
};

exports.handler = async () => {
  return await apiCanaryBlueprint();
};
