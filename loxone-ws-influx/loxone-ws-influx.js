//
// Author: R.A.Rainton <robin@rainton.com>
//
// Simple script to import Loxone stats into Influx DB.
//
// Most of this is shamelessly copied from Alladdin's test harness:
// https://github.com/alladdin/node-lox-ws-api-testing
//
// Config file is JSON format, something like...
// Get the Loxone UUIDs from the stat filenames, web interface, etc.
// 
//{
//	"loxone" : {
//		"host": "your.loxone.miniserver",
//		"username": "someusername",
//		"password": "somepasword"
//	},
//	
//	"influxdb" : {
//		"host": "your.influxdb.host",
//		"database": "yourdb"
//	},
//	
//	"uuids" : {
//		"1234abcd-037d-9763-ffffffee1234abcd": {"measurement": "temperature", "tags": {"room": "Kitchen"} },
//		"1234abcd-005f-8965-ffffffee1234abcd": {"measurement": "humidity", "tags": {"room": "Kitchen"} },
//		"1234abcd-0052-0f08-ffffffee1234abcd": {"measurement": "AnythingYouLike", "tags": {"lots": "OfTags", "AsMany": "AsYouLike"} }
//	}
//}
//
// This code automatically adds the tags, 'uuid' and 'src' to all values.
//

const config = require("config");
var LoxoneAPI = require('node-lox-ws-api');
var lox = new LoxoneAPI(config.loxone.host, config.loxone.username, config.loxone.password, true, 'AES-256-CBC' /*'Hash'*/);

const Influx = require('influx');
const influxdb = new Influx.InfluxDB({
	host: config.influxdb.host,
	database: config.influxdb.database
});

var debug = false;
var interval;

function log_error(message) {
    console.log((new Date().toISOString())+' ERROR : '+message);
}

function log_info(message) {
    console.log((new Date().toISOString())+' INFO : '+message);
}

function log_debug(message) {
    if (debug){
        console.log((new Date().toISOString())+' DEBUG: '+message);
    }
}

function limit_str(text, limit){
    limit = typeof limit !== 'undefined' ? limit : 100;
    text = ''+text;
    if (text.length <= limit){
        return text;
    }
    return text.substr(0, limit) + '...('+text.length+')';
}

lox.on('connected', function() {
    log_info("Loxone connected!");
});

lox.on('close', function() {
    log_info("Loxone closed!");
});

lox.on('abort', function() {
    log_info("Loxone aborted!");
    process.exit();
});

lox.on('close_failed', function() {
    log_info("Loxone close failed!");
    process.exit();
});

lox.on('connect_failed', function(error) {
    log_info('Loxone connect failed!');
});

lox.on('connection_error', function(error) {
    log_info('Loxone connection error: ' + error.toString());
});

lox.on('auth_failed', function(error) {
    log_info('Loxone auth error: ' + JSON.stringify(error));
});

lox.on('authorized', function() {
    log_info('Loxone authorized');
    setTimeout(function(){ lox.send_command('jdev/cfg/version') }, 5000);
});

lox.on('update_event_value', function(uuid, evt) {
    if (uuid in config.uuids) {
		log_info('Update event value: uuid='+uuid+', evt='+limit_str(evt, 100)+'');
		var writeData = config.uuids[uuid];
		writeData.tags["uuid"] = uuid;
		writeData.tags["src"] = "ws";
		writeData.fields = { "value" : evt }
		influxdb.writePoints([ writeData ]).catch(err => {
			log_error(`Error saving data to InfluxDB! ${err.stack}`)
		});
	} else {
		log_debug('Ignoring event value: uuid='+uuid+', evt='+limit_str(evt, 100)+'');
	}
});

process.on('SIGINT', function () {
    lox.abort();
});

lox.connect();
