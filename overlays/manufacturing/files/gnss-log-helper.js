/**
 * gnss-log-helper.js
 *
 * Two modes (default: validate):
 *   validate        -- Assert PRN 8 appears with SNR > 35 at least twice; exits 0 on pass, 1 on fail.
 *   parse (--parse) -- Convert raw GNSS NMEA sentences into readable output for downstream tools (LabVIEW, humans).
 *
 * Usage:
 *   node gnss-log-helper.js <path-to-log-file> [--parse]
 *   node gnss-log-helper.js --test         # run embedded self-test
 */
'use strict';

const fs = require('fs');
const {parseNmeaSentence} = require('nmea-simple');

/** Embedded test data for self-test mode */
const testData = `$GPGSV,1,1,04,02,,,49,15,,,35,26,,,49,29,,,35,1*69
$GPGSV,3,1,11,02,,,39,08,,,50,09,,,36,15,,,35,1*6D
$GPGSV,3,2,11,17,,,36,20,,,49,22,,,50,26,,,40,1*6C
$GPGSV,3,3,11,27,,,36,29,,,35,31,,,34,1*6C
$GPGSV,3,1,09,02,,,52,08,,,39,09,,,36,10,,,33,1*65
$GPGSV,3,2,09,17,,,36,20,,,37,22,,,53,26,,,53,1*6D
$GPGSV,3,3,09,27,,,36,1*6D
$GPGSV,2,1,07,02,,,39,08,,,51,13,,,36,20,,,51,1*65
$GPGSV,2,2,07,22,,,53,24,,,39,26,,,40,1*69
$GPGSV,3,1,09,02,,,52,03,,,34,08,,,39,13,,,31,1*6C
$GPGSV,3,2,09,20,,,52,22,,,53,24,,,39,26,,,40,1*63
$GPGSV,3,3,09,30,,,34,1*69
$GPGSV,3,1,10,02,,,39,06,,,35,08,,,39,11,,,50,1*68
$GPGSV,3,2,10,13,,,36,20,,,51,21,,,36,22,,,54,1*62
$GPGSV,3,3,10,26,,,40,32,,,51,1*60
$GPGSV,2,1,08,06,,,35,07,,,35,08,,,39,11,,,49,1*61
$GPGSV,2,2,08,20,,,34,21,,,36,26,,,40,32,,,52,1*69
$GPGSV,2,1,06,08,,,39,11,,,50,12,,,36,20,,,51,1*66
$GPGSV,2,2,06,26,,,40,32,,,51,1*67
$GPGSV,2,1,07,04,,,35,08,,,39,11,,,49,12,,,36,1*6B
$GPGSV,2,2,07,20,,,34,26,,,40,29,,,36,1*68`;

/**
 * Extract valid GPGSV sentences and their parsed objects
 */
function extractSentences(raw) {
	return raw
		.split(/\r?\n/)
		.map(line => line.trim())
		.filter(line => line && !line.includes('\x03') && !line.includes('^C') && line.startsWith('$GPGSV'))
		.map(line => {
			try {
				const parsed = parseNmeaSentence(line);
				return {line, parsed};
			} catch (err) {
				console.error(`PARSE ERROR: failed to parse NMEA sentence: ${line}`);
				return null;
			}
		})
		.filter(entry => entry !== null);
}

/**
 * Print parsed GPGSV sentences in human-readable format
 */
function printLog(entries) {
	if (!entries.length) {
		console.warn('WARNING: no GPGSV sentences found in log file');
		return;
	}
	entries.forEach(({line, parsed}) => {
		console.log(`GPGSV Sentence: ${line}`);
		parsed.satellites.forEach((sat, idx) => {
			console.log(`  Satellite ${idx + 1}: PRN=${sat.prnNumber}, SNR=${sat.SNRdB || 'N/A'} dB-Hz`);
		});
	});
}

/**
 * Validate presence of PRN 8 with SNR>35 at least twice
 */
function runValidation(entries) {
	const count = entries.reduce((acc, {parsed}) => (
		acc + (parsed.satellites.some(sat => sat.prnNumber === 8 && sat.SNRdB > 35) ? 1 : 0)
	), 0);

	console.log('Running GNSS Validation...');
	if (count >= 2) {
		console.log(`Validation success: PRN 8 with SNR>35 found ${count} times`);
		return true;
	} else {
		console.log(`Validation failure: PRN 8 with SNR>35 found ${count} times, expected at least 2`);
		return false;
	}
}

/** CLI handling */
const args = process.argv.slice(2);

if (args.includes('--test')) {
	const entries = extractSentences(testData);
	const ok = runValidation(entries);
	printLog(entries);
	console.log(`Self-test complete`);
	console.log(`${ok ? 'PASS' : 'FAIL'}`);
	process.exit(ok ? 0 : 1);
}

const fileArg = args.find(arg => !arg.startsWith('--'));
const modeParse = args.includes('--parse');
const modeValidate = !modeParse;

if (!fileArg) {
	console.error('Usage: node gnss-log-helper.js <path-to-log-file> [--parse]');
	process.exit(1);
}

if (!fs.existsSync(fileArg)) {
	console.error(`ERROR: Log file not found: ${fileArg}`);
	process.exit(1);
}

const raw = fs.readFileSync(fileArg, 'utf8');
const entries = extractSentences(raw);

if (modeParse) {
	printLog(entries);
	process.exit(0);
}

if (modeValidate) {
	printLog(entries);
	const ok = runValidation(entries);
	process.exit(ok ? 0 : 1);
}
