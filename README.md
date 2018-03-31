# loxone-stats-influx

Scripts for importing statistics from Loxone to InfluxDB. Very much beta. Use at your own risk!

### loxone_stats_influx_import.pl

Reads from a directory of raw Loxone statistics files and adds to InfluxDB.

### loxone-ws-influx

Node.js app to connect to Loxone miniserver and add changed values received to InfluxDB in real time. Runs standalone or in a Docker container.

## Usage

The idea is that these share a common JSON config file. Create `.loxone_stats_influx` in your home dir and link/copy into the `config` folder for the Node.js app.

They can co-exist happily, just be aware of averaging that might be going on in your Loxone installation which might create different values at the same 'time' (on the hour, 5 minute boundary, etc) when read from statistic files.

At the very least, one can create the JSON config file for an existing set of statistics, import many existing files from Loxone then either do this periodically (every hour for example) or switch to using WS only update from that point on.

## Credits

Most of the Node.js code is shamelessly copied from Alladdin's test harness: https://github.com/alladdin/node-lox-ws-api-testing
