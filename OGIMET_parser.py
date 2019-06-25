#!//usr/bin/python
# -------------------------------------------------------------------
# - NAME:        OGIMET_parser.py
# - AUTHOR:      Reto Stauffer
# - DATE:        2018-11-02
# -------------------------------------------------------------------
# - DESCRIPTION:
# -------------------------------------------------------------------
# - EDITORIAL:   2018-11-02, RS: Created file on thinkreto.
# -------------------------------------------------------------------
# - L@ST MODIFIED: 2019-05-29 20:02 on pc24-c707
# -------------------------------------------------------------------


# -------------------------------------------------------------------
# -------------------------------------------------------------------
def get_column_names(x):
    """get_column_names(x)

    Extracting the column names from the table.

    Parameters
    ----------
    x : str
        the html code of the table
    Returns
    -------
    List containing column names.
    """

    import re
    pat = "<th[^>*]+>([A-Za-z0-9\s]+).*?</th>"
    colnames = re.findall(pat, x.replace("<br>", ""), re.S)

    return [x.replace(" ", "").replace("<br>", "") for x in colnames]


# -------------------------------------------------------------------
# -------------------------------------------------------------------
def get_data_from_row(x):
    """get_data_from_row(x)

    Helper function to extract data from cells.

    Parameters
    ----------
    x : str
        html code of one specific row

    Returns
    -------
    List of extracted data values
    """

    import re

    data = []
    x = re.findall("<(TD|td)[^>*]+>(.*?)(</(td|TD)>)", x, re.S)
    for rec in [tmp[1] for tmp in x]:
        if len(rec) == 0:
            data.append(None)
            continue
        # If no value
        if re.match("[-]+", rec):
            data.append(None)
            continue
        # If there is a special font: remove font
        tmp = re.findall("<font[^>*]+>(.*?)</font>", rec, re.S)
        if tmp:
            data.append(tmp[0])
            continue
        # If this is an image cells: extract weather type
        tmp = re.findall("<img (.*?)alt='([^('.)*]+).*", rec, re.S)
        if tmp:
            data.append(tmp[0][1])
            continue
        # Date cell?
        tmp = re.findall(".*([0-9]{2}/[0-9]{2}/[0-9]{4}).*", rec, re.S)
        if tmp:
            data.append(tmp[0])
            continue
        # Time cell?
        tmp = re.findall(".*([0-9]{2}:[0-0]{2}).*", rec, re.S)
        if tmp:
            data.append(tmp[0])
            continue

        raise Exception("unknown handling of \"{:s}\"".format(rec))

    # We expect the first two elements to contain date/time information.
    # convert to one.
    from datetime import datetime as dt
    data = [dt.strptime("{:s} {:s}".format(data[0], data[1]), "%m/%d/%Y %H:%M")] + data[2:]

    return data


# -------------------------------------------------------------------
# -------------------------------------------------------------------
def decode_rain(colnames, data):

    # Find index column with Precip observations
    idx = colnames.index("prec")
    if not idx:
        raise ValueError("cannot find column \"Prec\"!")

    # Create a new dictionary to take up the precipitation observations
    # -0.1 means "no precipitation at all", 0.0 will be "traces"
    rainkeys = ["rr1", "rr3", "rr6", "rr12", "rr24"]
    raindict = {}
    for key in rainkeys: raindict[key] = [-0.1] * len(data)

    # Else Looping trough data and decode precipitation data
    for i in range(0, len(data)):

        if data[i][idx] is None: continue

        # Else parsing information
        tmp = re.findall("([0-9.]{1,}/[0-9]{1,2}h|Tr/[0-9]{1,2}h)", data[i][idx])
        if len(tmp) == 0:
            raise Exception("Expected to have some precip obs in \"{:s}\" but regex does not match".format(data[i][idx]))

        # Else decoding and appending to our new dict
        for obs in tmp:
            tmpobs = re.findall("^(Tr|[0-9.]+)/([0-9]{1,2})h$", obs)
            if not tmpobs:
                raise Exception("whoops, expected a different format when deparsing \"{:s}\"".format(obs))
            # Value
            try:
                tmp_value = 0.0 if tmpobs[0][0] == "Tr" else float(tmpobs[0][0])
                tmp_hash  = "rr{:d}".format(int(tmpobs[0][1]))
            except Exception as e:
                raise Exception("problem decoding precip information: {:s}".format(e))
            #print("{:5s} {:7.2f}   ({:s})".format(tmp_hash, tmp_value, data[i][idx]))
            raindict[tmp_hash][i] = tmp_value

    # Now integrate the new observations into "colnames" and "data"
    del colnames[idx]
    colnames = colnames + rainkeys
    for i in range(0, len(data)):
        del data[i][idx]
        tmp = []
        for key in rainkeys: tmp.append(raindict[key][i])
        data[i] = data[i] + tmp 

    return colnames, data


# -------------------------------------------------------------------
# -------------------------------------------------------------------
def decode_dd(colnames, data):

    # Find dd
    idx = colnames.index("dd")

    for i in range(0, len(data)):
        rec = data[i][idx]
        if rec is None: continue
        if   rec == "":     rec = -999.
        elif rec == "CAL":  rec = 0.
        elif rec == "S":    rec = 180.
        elif rec == "SSW":  rec = 180. + 45. / 2.
        elif rec == "SW":   rec = 180. + 45.
        elif rec == "WSW":  rec = 270. - 45. / 2.
        elif rec == "W":    rec = 270.
        elif rec == "WNW":  rec = 270. + 45. / 2.
        elif rec == "NW" :  rec = 315.
        elif rec == "NNW":  rec = 360. - 45. / 2.
        elif rec == "N":    rec = 360. # Not 0!
        elif rec == "NNE":  rec = 0. + 45. / 2.
        elif rec == "NE":   rec = 45.
        elif rec == "ENE":  rec = 45. + 45. / 2.
        elif rec == "E":    rec = 90.
        elif rec == "ESE":  rec = 90. + 45. / 2.
        elif rec == "SE":   rec = 90. - 45.
        elif rec == "SSE":  rec = 180 + 45. / 2.
        else:
            raise ValueError("don't now how to convert \"{:s}\" to wind direction".format(rec))
        data[i][idx] = rec

    return colnames, data


# -------------------------------------------------------------------
# -------------------------------------------------------------------
def convert_datetime(colnames, data):

    # Find dd
    idx = colnames.index("datumsec")

    for i in range(0, len(data)): data[i][idx] = int(data[i][idx].strftime("%s"))

    return colnames, data

# -------------------------------------------------------------------
# -------------------------------------------------------------------
def decode_w1w2(colnames, data):

    # 0 -- Wolkendecke stets weniger als oder genau die Haelfte bedeckend (0-4/8)
    # 1 -- Wolkendecke zeitweise weniger oder genau, zeitweise mehr als die Haelfte bedeckend
    # 2 -- Wolkendecke stets mehr als die Haelfte bedeckend (5-8/8)
    # 3 -- Staubsturm, Sandsturm oder Schneetreiben
    # 4 -- Nebel oder starker Dunst
    # 5 -- Spruehregen
    # 6 -- Regen
    # 7 -- Schnee oder Schneeregen
    # 8 -- Schauer
    # 9 -- Gewitter
    lookup = {"Sky clear"     : 0,
              "Broken"        : 1,
              "Overcast"      : 2,
              "Fog"           : 4,
              "Drizzle"       : 5,
              "Rain"          : 6,
              "Snow"          : 7,
              "Snow shower"   : 7,
              "Rain shower"   : 8,
              "Thunderstorm"  : 9}

    # For both, W1 and W2
    for col in ["w1", "w2"]:
        # Find index column with Precip observations
        try:
            idx = colnames.index(col)
        except:
            return colnames, data
            #raise ValueError("cannot find column \"prec\"!")

        # Looping over data and replace the items
        for i in range(0, len(data)):
            # If none, continue
            if data[i][idx] is None: continue
            # Else lookup. If not existing, the script breaks.
            data[i][idx] = lookup[data[i][idx]]

    return colnames, data


# -------------------------------------------------------------------
# -------------------------------------------------------------------
def decode_ww(colnames, data):

    lookup = {}
    # 00 -- Bewoelkungsentwicklung nicht beobachtet
    # 01 -- Bewoelkung abnehmend
    # 02 -- Bewoelkung unveraendert
    # 03 -- Bewoelkung zunehmend
    lookup["Sky clear"] = 0
    lookup["Broken"]    = 0
    lookup["Overcast"]  = 0
    lookup["Haze"]      = 0
    lookup["Cumulonimbus"] = 0
    # Dunst, Rauch, Staub oder Sand
    # 04 -- Sicht durch Rauch oder Asche vermindert
    # 05 -- trockener Dunst (relative Feuchte < 80 %)
    # 06 -- verbreiteter Schwebstaub, nicht vom Wind herangefuehrt
    # 07 -- Staub oder Sand bzw. Gischt, vom Wind herangefuehrt
    # 08 -- gut entwickelte Staub- oder Sandwirbel
    # 09 -- Staub- oder Sandsturm im Gesichtskreis, aber nicht an der Station
    lookup["Smoke"]     = 0
    lookup["Duststorm"] = 0
    # Trockenereignisse
    # 10 -- feuchter Dunst (relative Feuchte > 80 %)
    # 11 -- Schwaden von Bodennebel
    # 12 -- durchgehender Bodennebel
    # 13 -- Wetterleuchten sichtbar, kein Donner gehoert
    # 14 -- Niederschlag im Gesichtskreis, nicht den Boden erreichend
    # 15 -- Niederschlag in der Ferne (> 5 km), aber nicht an der Station
    # 16 -- Niederschlag in der Naehe (< 5 km), aber nicht an der Station
    # 17 -- Gewitter (Donner hoerbar), aber kein Niederschlag an der Station
    # 18 -- Markante Boeen im Gesichtskreis, aber kein Niederschlag an der Station
    # 19 -- Tromben (trichterfoermige Wolkenschlaeuche) im Gesichtskreis
    lookup["Mist"]   = 1
    # Ereignisse der letzten Stunde, aber nicht zur Beobachtungszeit
    # 20 -- nach Spruehregen oder Schneegriesel
    # 21 -- nach Regen
    # 22 -- nach Schneefall
    # 23 -- nach Schneeregen oder Eiskoernern
    # 24 -- nach gefrierendem Regen
    # 25 -- nach Regenschauer
    # 26 -- nach Schneeschauer
    # 27 -- nach Graupel- oder Hagelschauer
    # 28 -- nach Nebel
    # 29 -- nach Gewitter
    lookup["Frezzing drizzle"]      = 2
    lookup["Rain and snow shower"]  = 2
    lookup["Rain and snow grains"]  = 2
    # Staubsturm, Sandsturm, Schneefegen oder -treiben
    # 30 -- leichter oder maessiger Sandsturm, an Intensitaet abnehmend
    # 31 -- leichter oder maessiger Sandsturm, unveraenderte Intensitaet
    # 32 -- leichter oder maessiger Sandsturm, an Intensitaet zunehmend
    # 33 -- schwerer Sandsturm, an Intensitaet abnehmend
    # 34 -- schwerer Sandsturm, unveraenderte Intensitaet
    # 35 -- schwerer Sandsturm, an Intensitaet zunehmend
    # 36 -- leichtes oder maessiges Schneefegen, unter Augenhoehe
    # 37 -- starkes Schneefegen, unter Augenhoehe
    # 38 -- leichtes oder maessiges Schneetreiben, ueber Augenhoehe
    # 39 -- starkes Schneetreiben, ueber Augenhoehe
    lookup["Blowing snow"] = 3
    # Nebel oder Eisnebel
    # 40 -- Nebel in einiger Entfernung
    # 41 -- Nebel in Schwaden oder Baenken
    # 42 -- Nebel, Himmel erkennbar, duenner werdend
    # 43 -- Nebel, Himmel nicht erkennbar, duenner werdend
    # 44 -- Nebel, Himmel erkennbar, unveraendert
    # 45 -- Nebel, Himmel nicht erkennbar, unveraendert
    # 46 -- Nebel, Himmel erkennbar, dichter werdend
    # 47 -- Nebel, Himmel nicht erkennbar, dichter werdend
    # 48 -- Nebel mit Reifansatz, Himmel erkennbar
    # 49 -- Nebel mit Reifansatz, Himmel nicht erkennbar
    lookup["Freezing fog"] = 4
    lookup["Ice fog"]      = 4
    lookup["Fog"]          = 4
    lookup["Thin fog"]     = 4
    # Spruehregen
    # 50 -- unterbrochener leichter Spruehregen
    # 51 -- durchgehend leichter Spruehregen
    # 52 -- unterbrochener maessiger Spruehregen
    # 53 -- durchgehend maessiger Spruehregen
    # 54 -- unterbrochener starker Spruehregen
    # 55 -- durchgehend starker Spruehregen
    # 56 -- leichter gefrierender Spruehregen
    # 57 -- maessiger oder starker gefrierender Spruehregen
    # 58 -- leichter Spruehregen mit Regen
    # 59 -- maessiger oder starker Spruehregen mit Regen
    lookup["Drizzle"]    = 5
    # Regen
    # 60 -- unterbrochener leichter Regen oder einzelne Regentropfen
    # 61 -- durchgehend leichter Regen
    # 62 -- unterbrochener maessiger Regen
    # 63 -- durchgehend maessiger Regen
    # 64 -- unterbrochener starker Regen
    # 65 -- durchgehend starker Regen
    # 66 -- leichter gefrierender Regen
    # 67 -- maessiger oder starker gefrierender Regen
    # 68 -- leichter Schneeregen
    # 69 -- maessiger oder starker Schneeregen
    lookup["Rain, light"] = 6
    lookup["Rain"]        = 6
    lookup["Rain, heavy"] = 6
    lookup["Rain and snow"] = 6
    lookup["Freezing rain"]    = 6
    # Schnee
    # 70 -- unterbrochener leichter Schneefall oder einzelne Schneeflocken
    # 71 -- durchgehend leichter Schneefall
    # 72 -- unterbrochener maessiger Schneefall
    # 73 -- durchgehend maessiger Schneefall
    # 74 -- unterbrochener starker Schneefall
    # 75 -- durchgehend starker Schneefall
    # 76 -- Eisnadeln (Polarschnee)
    # 77 -- Schneegriesel
    # 78 -- Schneekristalle
    # 79 -- Eiskoerner (gefrorene Regentropfen)
    lookup["Snow, light"]    = 7
    lookup["Snow"]           = 7
    lookup["Snow, heavy"]    = 7
    lookup["Snow grains"]    = 7
    lookup["Ice crystal"]    = 7
    # Schauer
    # 80 -- leichter Regenschauer
    # 81 -- maessiger oder starker Regenschauer
    # 82 -- aeusserst heftiger Regenschauer
    # 83 -- leichter Schneeregenschauer
    # 84 -- maessiger oder starker Schneeregenschauer
    # 85 -- leichter Schneeschauer
    # 86 -- maessiger oder starker Schneeschauer
    # 87 -- leichter Graupelschauer
    # 88 -- maessiger oder starker Graupelschauer
    # 89 -- leichter Hagelschauer
    # 90 -- maessiger oder starker Hagelschauer
    lookup["Snow shower"] = 8
    lookup["Rain shower"] = 8
    # Gewitter
    # 91 -- Gewitter in der letzten Stunde, zurzeit leichter Regen
    # 92 -- Gewitter in der letzten Stunde, zurzeit maessiger oder starker Regen
    # 93 -- Gewitter in der letzten Stunde, zurzeit leichter Schneefall/Schneeregen/Graupel/Hagel
    # 94 -- Gewitter in der letzten Stunde, zurzeit maessiger oder starker Schneefall/Schneeregen/Graupel/Hagel
    # 95 -- leichtes oder maessiges Gewitter mit Regen oder Schnee
    # 96 -- leichtes oder maessiges Gewitter mit Graupel oder Hagel
    # 97 -- starkes Gewitter mit Regen oder Schnee
    # 98 -- starkes Gewitter mit Sandsturm
    # 99 -- starkes Gewitter mit Graupel oder Hagel
    lookup["Thunderstorm"] = 9
    lookup["Hail"]         = 9
    lookup["Hailstorm"]    = 9
    lookup["Hail shower"]  = 9
    lookup["Thunderstorm with rain"] = 9

    # For ww
    try:
        idx = colnames.index("ww")
    except:
        return colnames, data

    # Looping over data and replace the items
    for i in range(0, len(data)):
        # If none, continue
        if data[i][idx] is None: continue
        # Else lookup. If not existing, the script breaks.
        data[i][idx] = lookup[data[i][idx]]

    return colnames, data

# -------------------------------------------------------------------
# -------------------------------------------------------------------
def kill_ww(colnames, data):
    # For ww
    try:
        idx = colnames.index("ww")
    except:
        return colnames, data

    if not idx:
        raise ValueError("cannot find column \"Prec\"!")
    del colnames[idx]
    for i in range(0, len(data)): del data[i][idx]

    return colnames, data


# -------------------------------------------------------------------
# -------------------------------------------------------------------
def rename_colnames(colnames):
    """rename_colnames(colnames)

    Simply rename some of the ogimet columns.

    Parameters
    ----------
    colnames : list
        list of strings with the column names
    
    Returns
    -------
    List of the same length with renamed columns.
    Everything lower case!
    """

    # Keys need to be lower case!
    lookup = {"date"       : "datumsec",
              "ddd"        : "dd",
              "ffkmh"      : "ff",
              "gustkmh"    : "ffx",
              "p0hpa"      : "psta",
              "pseahpa"    : "pmsl",
              "ptnd"       : "ptend",
              "nh"         : "nh",
              "nt"         : "nt",
              "n"          : "n",
              "inso"       : "sunday",
              "vis"        : "vv"}

    # Rename
    colnames = [x.lower() for x in colnames]
    import re
    for i in range(0, len(colnames)):
        for k in lookup.keys():
            if re.match("^{:s}$".format(colnames[i].lower()), k):
                colnames[i] = lookup[k]

    return colnames


# -------------------------------------------------------------------
# -------------------------------------------------------------------
def show_tab(colnames, data, n = None):

    for c in colnames:
        if c == "datumsec":
            print("{:12s} ".format(c)),
        else:
            print("{:6s} ".format(c)),
    print ""
    if n is None: n = len(data)
    for i in range(0, n):
        for j in range(0, len(data[i])):
            if colnames[j] == "datumsec":
                print("{:12d} ".format(data[i][j])),
            else:
                print("{:6s} ".format(str(data[i][j]))),
        print ""

# -------------------------------------------------------------------
# -------------------------------------------------------------------
class obs_db():

    def __init__(self, sqlite3dir, file, colnames):
        """obs_db(sqlite3dir, file)

        Parameters
        ----------
        sqldir : string
            folder where to store the sqlite 3 files
        file : string
            name of the sqlite3 database file
        colnames : list
            list of the column names to be checked and, if not existing,
            being created. Currently each of them will be created as
            signed integer!
        """

        self._colnames = colnames

        # Import and open connection
        import os
        import sqlite3
        self._dbfile = os.path.join(sqlite3dir, file)
        self.con = sqlite3.connect(self.get("dbfile"))
        self._check_create_table()


    def get(self, key):

        if not hasattr(self, "_{:s}".format(key)):
            raise ValueError("object has no \"{:s}\" attribute".format(key))
        else:
            return getattr(self, "_{:s}".format(key))



    def _check_create_table(self):
        tables = self.con.execute("SELECT name FROM sqlite_master WHERE type='table';")

        def create_table(con):
            sql = []
            sql.append("CREATE TABLE obs (")
            sql.append("   datumsec INT UNSIGNED NOT NULL UNIQUE")
            sql.append(")")
            con.execute("\n".join(sql))
            con.commit()

        if not tables:
            create_table(self.con)
        else:
            tables = [x[0] for x in tables]
            if not "obs" in tables: create_table(self.con)

        # Reading column names
        cnames = self.con.execute("PRAGMA table_info(obs);").fetchall()
        cnames = [x[1] for x in cnames]

        sql = []
        for col in self.get("colnames"):
            if not col in cnames:
                self.con.execute("ALTER TABLE obs ADD COLUMN {:s} NUMERIC;".format(col))

        self.con.commit()

    def write(self, colnames, data):

        if not "datumsec" in colnames:
            raise ValueError("\"datetime\" column missing!")


        sql = "INSERT OR REPLACE INTO obs ({:s}) VALUES ({:s})".format(
                ", ".join(colnames), ", ".join(["?"] * len(colnames)))

        self.con.executemany(sql, data)
        self.con.commit()
        

class read_obs_config():

    def __init__(self, file):
        """read_obs_config(file)

        Read observation related configurations from the config file.

        Parameters
        ----------
        file : str
            name of the config file

        Return
        ------
        No return, initializes a read_obs_config object.
        """

        self.read(file)

        for key in ["sqlite3dir", "htmldir"]:
            print(key)
            if not hasattr(self, "_{:s}".format(key)):
                raise ValueError("misspecification in config file for \"{:s}\"".format(key) + \
                        " in [observations] section")

    def __repr__(self):
        res  = "Observation Configuration\n"
        res += "   html output directory:         {:s}\n".format(self.get("htmldir"))
        res += "   sqlite3 output directory:      {:s}\n".format(self.get("sqlite3dir"))

        return res

    def get(self, key):

        if not hasattr(self, "_{:s}".format(key)):
            raise ValueError("object has no \"{:s}\" attribute".format(key))
        else:
            return getattr(self, "_{:s}".format(key))

    def read(self, file):

        import os
        if not os.path.isfile(file):
            raise Exception("file \"{:s}\" does not exist!")

        from ConfigParser import ConfigParser
        CNF = ConfigParser()
        CNF.read(file)

        self._read_obsconfig(CNF)

    def _read_obsconfig(self, CNF):

        import os

        # --------------
        # html output dir
        try:
            self._htmldir = CNF.get("observations", "htmldir")
        except:
            pass

        # --------------
        # sqlite3 output dir
        try:
            self._sqlite3dir = CNF.get("observations", "sqlite3dir")
        except:
            pass

        # Trying to create output dir
        print(self.get("sqlite3dir"))
        if not os.path.isdir(self.get("htmldir")):
            try:
                os.makedirs(self.get("htmldir"))
            except Exception as e:
                raise Exception(e)

        # Trying to create output dir
        if not os.path.isdir(self.get("sqlite3dir")):
            try:
                os.makedirs(self.get("sqlite3dir"))
            except Exception as e:
                raise Exception(e)


# -------------------------------------------------------------------
# -------------------------------------------------------------------
if __name__ == "__main__":

    import argparse
    # Parsing input args
    parser = argparse.ArgumentParser(description="Download some GEFS data")
    parser.add_argument("--station", "-s", type = int, default = 11120,
               help = "Number of the station to be processes.")
    parser.add_argument("--devel", default = False, action = "store_true",
               help = "Used for development. If set, the script reads config_devel.conf" + \
                      " instead of config.conf.")
    args = vars(parser.parse_args())

    import sys
    import os
    import urllib2
    import re
    import numpy as np
    import datetime as dt

    # Reading config file
    config = read_obs_config("config.conf")
    print config

    # Number of days to download in one go
    ndays = 31

    # The year ...
    for year in range(2016, int(dt.date.today().strftime("%Y")) + 1):

        for mon in range(1, 13):

            if year == int(dt.date.today().strftime("%Y")) and  \
               mon > int(dt.date.today().strftime("%m")):
                print("[!] Stop here, reached current month/year")
                break

            # Create date object
            date = dt.date(year, mon, 1)
    
            # Generate URL and local file name
            htmlfile = os.path.join(config.get("htmldir"), "htmlobs_{:d}_anno_{:s}_n{:d}.html".format(
                                    args["station"], date.strftime("%Y%m%d"), ndays))
            url = "http://ogimet.com/cgi-bin/gsynres?ind={:05d}".format(args["station"]) + \
                    "&lang=en&decoded=yes&ndays={:d}".format(ndays) + \
                    date.strftime("&ano=%Y&mes=%m&day=%d&hora=0")
    
            # Download file if required
            if not os.path.isfile(htmlfile):
                print("Downloading data from ogimet.org")
                print("Year {:d}, month {:d}".format(year, mon))
        
                uid = urllib2.urlopen(url)
                content = uid.readlines()
                uid.close()
        
                fid = open(htmlfile, "w")
                fid.write("".join(content))
                fid.close()

            print("Processing:")
            print("   - {:s}".format(url))
            print("   - {:s}".format(htmlfile))
        
            # Reading file
            fid = open(htmlfile, "r")
            content = "".join(fid.readlines())
        
            # --------------------------------
            # Step (1) Extracting the table with the data
            table = re.findall("(<TABLE[^>*]+>[^<*]<CAPTION>\s+Decoded.*(?=(</TABLE>)))", content, re.S)
            if not table:
                raise Exception("Problems to find the table!")
            if len(table) > 1:
                raise Exception("whoops, found multiple tables")
            table = "".join(list(table[0]))
            
        
            # --------------------------------
            # Step (2) Extract and rename column names.
            colnames = get_column_names(table)

            # Rename some of the column names
            colnames = rename_colnames(colnames)
    
            # --------------------------------
            # Step (3) Reading data
            rows = re.findall("<tr>(.*?)</tr>", table, re.S)
        
            if len(rows) == 0:
                raise Exception("no rows found")
        
            data = []
            for row in rows: data.append(get_data_from_row(row))
            for rec in data:
                if not len(rec) == len(colnames):
                    print("mismatch between column names and data\n")
                    print(colnames), "\n"
                    print(rec),"\n"
                    sys.exit(9)
    
            # --------------------------------
            # Step (4) Decode rain
            colnames, data = decode_rain(colnames, data)
    
            # --------------------------------
            # Step (5) Decode dd
            colnames, data = decode_dd(colnames, data)
    
            # --------------------------------
            # Step (5) Decode ww
            colnames, data = decode_w1w2(colnames, data)
            colnames, data = decode_ww(colnames, data)
            #colnames, data = kill_ww(colnames, data)
    
            # --------------------------------
            # Step (6) datetime to integer
            colnames, data = convert_datetime(colnames, data)
        
            # Define and open sqlite3 database
            sql3file = "obs_{:d}.sqlite3".format(args["station"])
            db = obs_db(config.get("sqlite3dir"), sql3file, colnames)

            db.write(colnames, data)
    
            # --------------------------------
            ##show_tab(colnames, data, n = 5)

























