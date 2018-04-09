# loxone-stats-influx

Scripts for importing statistics from Loxone to InfluxDB. Very much beta. Use at your own risk!

### loxone_stats_influx_import.pl

Reads from a directory of raw Loxone statistics files and adds to InfluxDB.

### loxone-ws-influx

Node.js app to connect to Loxone miniserver and add changed values received to InfluxDB in real time. Runs standalone or in a Docker container.

## Usage

The idea is that these share a common JSON config file. Create `.loxone_stats_influx` in your home dir and link/copy into the `config` folder for the Node.js app.

They can co-exist happily, just be aware of averaging that might be going on in your Loxone installation which might create different values at the same 'time' (on the hour, 5 minute boundary, etc) when read from statistic files.

There are 3 suggested ways these scripts could be used:

### Method 1

1. Create JSON config file.
2. Copy statistics files from Loxone to a local directory (use LFTP mirror or similar).
3. Run `loxone_stats_influx_import.pl`
4. Repeat steps 2 & 3 periodically (eg. place in a 1 hour cron file).

Pros: Quick and easy.
Cons: FTP, even just changed files, basically copies and loads all stats for the current month every run. InfluxDB doesn't care about the duplicates but this is hardly efficient. Stats are delayed in InfluxDB.

### Method 2

1. Create JSON config file.
2. Copy statistics files from Loxone to a local directory (use LFTP mirror or similar).
3. Run `loxone_stats_influx_import.pl`
4. Setup `loxone-ws-influx` Node.js app and run continuously from then on.

Pros: All your historical data is impored and from time of install updates are instant.
Cons: Setup for the Node.js app is slightly more involved.

### Method 2

1. Create JSON config file.
2. Setup `loxone-ws-influx` Node.js app and run continuously.

Pros: Only have to worry about the Node.js app and from time of install updates are instant.
Cons: Doesn't bring in historical data & setup for the Node.js app is slightly more involved.

## Credits

Most of the Node.js code is shamelessly copied from Alladdin's test harness: https://github.com/alladdin/node-lox-ws-api-testing
