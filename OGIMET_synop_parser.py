# -------------------------------------------------------------------
# - NAME:        OGIMET_synop_parser.py
# - AUTHOR:      Reto Stauffer
# - DATE:        2018-11-04
# -------------------------------------------------------------------
# - DESCRIPTION: Downloading and parsing data from IHD NOAA
# -------------------------------------------------------------------
# - EDITORIAL:   2018-11-04, RS: Created file on thinkreto.
# -------------------------------------------------------------------
# - L@ST MODIFIED: 2018-12-10 17:04 on marvin
# -------------------------------------------------------------------


import os
os.environ["TZ"] = "UTC"

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

        self._colnames = [x.lower() for x in colnames]

        # Import and open connection
        import os
        import sqlite3
        self._dbfile = os.path.join(sqlite3dir, file)
        self.con = sqlite3.connect(self.get("dbfile"))
        self._check_create_table()


    def get(self, key):
        """get(key)

        Parameters
        ----------
        key : str
            the attribute of the object which should be returned

        Returns
        -------
        In this case: return the value of the attribute if existing,
        else raise a ValueError.
        """

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

        colnames = [x.lower() for x in colnames]

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

        for key in ["sqlite3dir", "htmldir", "isddir"]:
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

        # ihd output dir
        try:
            self._isddir = CNF.get("observations", "isddir")
        except:
            pass

        # Trying to create output dir
        if not os.path.isdir(self.get("htmldir")):
            try:
                os.makedirs(self._htmldir)
            except Exception as e:
                raise Exception(e)

        # --------------
        # sqlite3 output dir
        try:
            self._sqlite3dir = CNF.get("observations", "sqlite3dir")
        except:
            pass

        # Trying to create output dir
        if not os.path.isdir(self.get("sqlite3dir")):
            try:
                os.makedirs(self._sqlite3dir)
            except Exception as e:
                raise Exception(e)

# -------------------------------------------------------------------
# -------------------------------------------------------------------
# Reading file
class get_synop_messages():

    import re

    # Extracting valid synop messages, pick date information.
    #                     stn        date           YYGGggi  stn    message
    regex = re.compile("^([0-9]+),([0-9,]{16}),AAXX\s(.{5})\s([0-9]+)\s([^=.*])[=]+$", re.M)

    def __init__(self, file, verbose = False):
        """get_synop_messages(file, verbose = False)

        Extract synop messages from .gz file (integrated surface data archive)

        Parameters
        ----------
        file : str
            path to the file to be read
        verbose : bool
            default False, if set to True each message will create some
            output on stdout. Development feature.
        """

        from os.path import isfile
        if not isinstance(verbose, bool):
            raise Exception("input verbose has to be boolean True or False")
        if not isfile(file):
            raise Exception("file \"{:s}\" does not exist".format(file))

        try:
            with open(file, "rb") as gid:
                content = gid.readlines()
        except Exception as e:
            raise Exception("problems reading \"{s:}\". {:s}".format(file, e))

        import re
        mtch = self.regex.findall("\n".join(content))
        if verbose: print("Found {:d} messages in file".format(len(mtch)))

        self._data = []
        for rec in mtch:
            # NIL message: skip
            if rec[4].strip() == "NIL": continue
            # Else prse
            tmp = synopmessage(rec, verbose)
            if verbose: print(tmp)
            self._data.append(tmp)


    def __call__(self):
        """
        Standard call simply returns the list of "synopmessage" objects.
        """

        return self._data


# -------------------------------------------------------------------
# -------------------------------------------------------------------
class synopmessage():

    import re

    # Regex expression is decoding (parts) of the FM-12 synop message
    # From documentation
    # 16-23 date
    # 24-27 time
    # 42-46 message type code
    regex = re.compile("^(\S{5})\s(\S{5})(\s00\S{3})?(\s1\S{4})?(\s2\S{4})?" + \
            "(\s3\S{4})?(\s4\S{4})?(\s5\S{4})?(\s6\S{4})?(\s7\S{4})?(\s8\S{4})?" + \
            "(\s9\S{4})?(\s333\s.*)?(?=\s[0-9]{3}\s)?.*?$", re.M) 

    # Regex expression to parse data from the clim block "333"
    # 0.... 1sTTT 2sTTT 3EsTT 4E'sss 55SSS 2FFFF 3FFFF 4FFFF 553SS 2FFFF
    # 3FFFF 4FFFF 6RRRt 7RRRR 8NChh 9SSss 
    rd   = "(\s0\S{4})?(\s1\S{4})?(\s2\S{4})?(\s3\S{4})?(\s4\S{4})?" + \
           "(\s55[^3][\S]{2})?(\s2\S{4})?(\s3\S{4})?(\s4\S{4})?(\s553\S{2})?" + \
           "(\s2\S{4})?(\s3\S{4})?(\s4\S{4})?(\s6\S{4})?(\s7\S{4})?"
    rd89 = "(\s[89].*)?"
    regex333 = re.compile("^333" + rd + rd89 + "(?=\s[0-9]{3}\s)?.*?$")

    # Parsing 8/9 blocks
    regex89 = re.compile("([89].{4}\s?)")

    def __init__(self, x, verbose = False):
        """synopmessage(x, verbose = False)

        Creates a small object containing all the information from one
        synop message.

        Parameters
        ----------
        x : tuple
            the tuple as returned by regex.findall(...) in get_synop_messages!
        verbose : bool
            default False, if set to True each message will create some
            output on stdout. Development feature.
        """

        if not isinstance(x, tuple):
            raise ValueError("wrong input type")
        if not len(x) == 5:
            raise ValueError("something wrong with input (length wrong)")

        if verbose:
            print("---------------------- (MSG)")
            print(x[4])

        import datetime as dt
        self._station   = int(x[0])
        self._datetime  = dt.datetime.strptime(x[1], "%Y,%m,%d,%H,%M")
        self._datumsec  = int(self._datetime.strftime("%s"))

        self._decode_YYGGggi(x[2])
        self._decode_message(x[4])

    def __repr__(self):

        res  = "Decodes Synop Message (devel output)\n"
        res += "  - Wind in knots:          {:s}\n".format(str(self.get("knots")))
        res += "  - Datetime                {:s}\n".format(self.get("datetime").strftime("%Y-%m-%d %H:%M"))
        res += "  - ir/ix/vv:               {:s} {:s} {:s}\n".format(
                str(self.get("ir")), str(self.get("ix")), str(self.get("vv")))
        res += "  - N/dd/ff:                {:s} {:s} {:s}\n".format(
                str(self.get("N")),str(self.get("dd")), str(self.get("ff")))
        res += "  - T/Td/rh:                {:s} {:s} {:s}\n".format(
                str(self.get("T")), str(self.get("Td")), str(self.get("rh")))
        res += "  - p/pmsl:                 {:s} {:s}\n".format(
                str(self.get("p")), str(self.get("pmsl")))
        res += "  - p change:               {:s} (ptend {:s})\n".format(
                str(self.get("pch")), str(self.get("ptend")))
        res += "  - precip 1/3/6/12/24:     {:s} {:s} {:s} {:s} {:s}\n".format(
                str(self.get("rr1")), str(self.get("rr3")),
                str(self.get("rr6")), str(self.get("rr12")), str(self.get("rr24")))
        res += "  - ww/W1/W2:               {:s} {:s} {:s}\n".format(
                str(self.get("ww")), str(self.get("W1")), str(self.get("W2")))
        res += "  - sun/sunday:             {:s} {:s}\n".format(
                str(self.get("sun")), str(self.get("sunday")))
        res += "  - ffinst/ffx:             {:s} {:s}\n".format(
                str(self.get("ffinst")), str(self.get("ffx")))

        return res

    def get_tuple(self, params):
        """get_tuple(param)

        Used to create the tuples for the database.

        Parameter
        ---------
        param : str or list of str
            string or list of strings, parameter names which should be
            returned as a tuple. Note that attributes which are not set
            will be handled as None.
        """

        if isinstance(params, str): params = [params]
        if not isinstance(params, list):
            raise ValueError("wrong input, requires str or list of str.")

        tmp = []
        for p in params: tmp.append(self.get(p))
        return tuple(tmp)

    def _decode_message(self, message):
        """_decode_messages(message)

        Decoding (parts) of a synop message. The message has to start
        with "iihVV ..." as delivered by ISD.
        FM-12 details see http://www.met.fu-berlin.de/~stefan/fm12.html

        Parameters
        ----------
        message : str
            the synop style message starting with iihVV ...
        """

        tmp = self.regex.findall(message)
        if not tmp:
            raise ValueError("problems decoding {:s}".format(message))

        tmp = [x.strip() for x in tmp[0]]
        # Decode the different blocks
        funs = ["iihVV", "Nddff", "00fff", "1sTTT", "2sTTT", "3PPPP",
                "4PPPP", "5appp", "6RRRt", "7wwWW", "8NCCC", "9GGgg","333"]

        for i in range(0, len(funs)):
            fun = getattr(self, "_decode_{:s}".format(funs[i]))
            fun(tmp[i])

    # ----------------------
    def _decode_YYGGggi(self, x):
        # I am only interested in the last piece which defines
        # whether the wind speed observations are in knots or
        # meters per second.
        if x[4] == "/":
            self._knots = None # No information about wind speed obs!
        elif int(x[4]) in [0, 1]:
            self._knots = False
        else:
            self._knots = True

    # ----------------------
    def _decode_iihVV(self, x):
        self._ir = None
        self._ix = None
        self._h  = None
        self._VV = None
        if len(x) == 0: return
        # Else decode
        self._ir = int(x[0])
        self._ix = int(x[1])
        self._h  = None if x[2]  == "/"  else int(x[2])
        if not x[3:] == "//":
            tmp = int(x[3:])
            if tmp <= 50:
                self._VV = tmp
            elif tmp <= 80:
                self._VV = (tmp - 50) * 10
            elif tmp <= 89:
                self._VV = (tmp - 80) * 5 + 30
            elif tmp in [90,91]:  self._VV = 0
            elif tmp == 92:       self._VV = 2
            elif tmp == 93:       self._VV = 5
            elif tmp == 94:       self._VV = 10
            elif tmp == 94:       self._VV = 10
            elif tmp == 95:       self._VV = 20
            elif tmp == 96:       self._VV = 40
            elif tmp == 97:       self._VV = 100
            elif tmp == 98:       self._VV = 200
            elif tmp == 99:       self._VV = 500

    # ----------------------
    def _decode_Nddff(self, x):
        self._N  = None
        self._dd = None
        self._ff = None
        if len(x) == 0: return
        self._N   = None if x[0] == "/" else int(x[0])
        if not x[1:3] == "//":
            self._dd  = int(x[1:3])
        if not x[3:] == "//":
            self._ff  = int(x[3:]) * 10
            if self._knots is None:
                raise Exception("YYGGggi did not provide any wind speed units, but now " + \
                        "wind speed in Nddff has been found! That's not good. Stop.")
            if self._knots:
                self._ff = int(float(self._ff) * 0.5144447)

    # ----------------------
    def _decode_00fff(self, x): 
        if len(x) == 0: return
        self._ff  = int(x[2:]) * 10# Overwrites self._ff of Nddff if set
        if self._knots is None:
            raise Exception("YYGGggi did not provide any wind speed units, but now " + \
                    "wind speed in 00fff has been found! That's not good. Stop.")
        if self._knots:
            self._ff = int(float(self._ff) * 0.5144447)

    # ----------------------
    def _decode_1sTTT(self, x): 
        self._T = None
        if len(x) == 0: return
        # Empty message
        if x[1:] == "////": return
        self._T = int(x[2:])
        if int(x[1]) == 1: self._T = -self._T

    # ----------------------
    def _decode_2sTTT(self, x): 
        self._rh = None
        self._Td = None
        if len(x) == 0: return
        # Empty message
        if x[1:] == "////": return
        # In this case we do have relative humidity
        # and not dewpoint temperature.
        if x[1] == "9":
            self._rh = int(x[2:])
        else:
            self._Td = int(x[2:])
            if int(x[1]) == 1: self._Td = -self._Td

    # ----------------------
    def _decode_3PPPP(self, x): 
        self._p = None
        if len(x) == 0: return
        # Empty message
        if x[1:] == "////": return
        # If 3PPP/: full hPa
        if re.match("^3[0-9]{3}/$", x):
            self._p = 10 * int(x[1:4])
        else:
            self._p = int(x[1:])
        if self._p < 500: self._p += 10000

    # ----------------------
    def _decode_4PPPP(self, x): 
        self._pmsl = None
        if len(x) == 0: return
        if x[1:] == "////": return
        # If 4PPP/: full hPa
        if re.match("^4[0-9]{3}/$", x):
            self._pmsl = 10 * int(x[1:4])
        else:
            self._pmsl = int(x[1:])
        if self._pmsl < 500: self._pmsl += 10000

    # ----------------------
    def _decode_5appp(self, x): 
        self._ptend = None
        self._pch   = None
        if len(x) == 0: return
        # Empty message
        if x[1] == "/": return
        # Else extract information
        self._ptend = int(x[1])
        if not x[2:] == "///":
            self._pch   = int(x[2:])
            if self._ptend > 5:
                self._pch = -self._pch

    # ----------------------
    def _decode_6RRRt(self, x): 
        self._tr   = None
        
        if len(x) == 0: return
        if x[4] == "/" or x[4] == "0": return
        # Empty message (no precip)
        if x[1:4] == "///": return

        # 0 -- nicht aufgefuehrter oder vor dem Termin endender Zeitraum
        # 1 -- 6 Stunden
        # 2 -- 12 Stunden
        # 3 -- 18 Stunden
        # 4 -- 24 Stunden
        # 5 -- 1 Stunde bzw. 30 Minuten (bei Halbstundenterminen)
        # 6 -- 2 Stunden
        # 7 -- 3 Stunden
        # 8 -- 9 Stunden
        # 9 -- 15 Stunden
        tr = self._tr = int(x[4])
        if   tr == 1:  hours = 6
        elif tr == 2:  hours = 12
        elif tr == 3:  hours = 18
        elif tr == 4:  hours = 24
        elif tr == 5:  hours = 1
        elif tr == 6:  hours = 2
        elif tr == 7:  hours = 3
        elif tr == 8:  hours = 9
        elif tr == 9:  hours = 15
        else:
            raise ValueError("unexpected value for tr")

        # 990 -- Spuren von Niederschlag, nicht messbar (< 0.05 mm)
        # 991 -- 0.1 mm
        # 992 -- 0.2 mm
        # ...
        # 999 -- 0.9 mm
        rr = int(x[1:4])
        if rr >= 990:   rr = rr - 990
        else:           rr = rr * 10

        # Store
        setattr(self, "_rr{:d}".format(hours), int(rr))

    # ----------------------
    def _decode_7wwWW(self, x): 
        self._ww = None
        self._W1 = None
        self._W2 = None
        if len(x) == 0: return
        if not x[1:3] == "//": self._ww = int(x[1:3])
        if not x[3] == "/":   self._W1 = int(x[3])
        if not x[4] == "/":   self._W2 = int(x[4])

    # ----------------------
    def _decode_8NCCC(self, x): 
        self._nh = None
        self._cl = None
        self._cm = None
        self._ch = None
        if len(x) == 0: return
        if not x[1] == "/": self._nh = int(x[1])
        if not x[2] == "/": self._cl = int(x[2])
        if not x[3] == "/": self._cm = int(x[3])
        if not x[4] == "/": self._ch = int(x[4])

    # ----------------------
    def _decode_9GGgg(self, x): 
        if len(x) == 0: return

    # ----------------------
    def _decode_333(self, x):
        if len(x) == 0: return

        # Else parse block 333
        tmp = self.regex333.findall(x)

        if not tmp: return
        tmp = [x.strip() for x in tmp[0]]

        # 0.... 1sTTT 2sTTT 3EsTT 4E'sss 55SSS 2FFFF 3FFFF 4FFFF 553SS 2FFFF
        # 3FFFF 4FFFF 6RRRt 7RRRR 8NChh 9SSss 
        funs = ["0XXXX", "1sTTT", "2sTTT", "3EsTT", "4Esss",
                "55SSS", "2FFFF", "3FFFF", "4FFFF", "553SS", "2FFFF",
                "3FFFF", "4FFFF", "6RRRt", "7RRRR", "89blocks"]
        if not len(tmp) == len(funs):
            raise ValueError("extracted blocks and function definition does not match!")
        for i in range(0, len(funs)):
            fun = getattr(self, "_decode_333_{:s}".format(funs[i]))
            fun(tmp[i])


    # ----------------------
    # Message which is unused in FM-12 format
    def _decode_333_0XXXX(self, x):
        # Unused
        return

    # ----------------------
    def _decode_333_1sTTT(self, x):
        self._Tmax12 = None
        if len(x) == 0: return
        self._Tmax12 = int(x[2:])
        if int(x[1]) == 1: self._Tmax12 = -self._Tmax12

    # ----------------------
    def _decode_333_2sTTT(self, x):
        self._Tmin12 = None
        self._Tmin15 = None
        if len(x) == 0: return
        t = int(x[2:])
        if int(x[1]) == 1: t = -t

        # Checking time
        hour = int(self.get("datetime").strftime("%H"))
        if hour == 9:
            self._Tmin15 = t
        else:
            self._Tmin12 = t

    # ----------------------
    def _decode_333_3EsTT(self, x):
        self._E    = None
        self._T5cm = None
        if len(x) == 0: return
        if not x[1] == "/": self._E = int(x[1])
        if not x[3:] == "//":
            self._T5cm = int(x[3:])
            if int(x[2]) == 1: self._T5cm = -self._T5cm

    # ----------------------
    def _decode_333_4Esss(self, x):
        self._Eschnee = None
        self._snh     = None
        if len(x) == 0: return
        # Schneehoehe in cm (997 = < 0.5 cm,
        # 998 = Flecken oder Reste, 999 = Angabe nicht moeglich)
        if not x[1] == "/":    self._Eschnee = int(x[1])
        if not x[2:] == "///": self._snh     = int(x[2:])

    # ----------------------
    def _decode_333_55SSS(self, x):
        self._sunday = None
        if len(x) == 0: return
        # Convert to minutes (what's delivered by BUFR)
        if not x[2:] == "///":
            self._sunday = int(x[2:]) * 360 # 10 * 3600

    # ----------------------
    def _decode_333_2FFFF(self, x):
        self._gloday = None
        if len(x) == 0: return
        self._gloday = int(x[1:])

    # ----------------------
    def _decode_333_3FFFF(self, x):
        self._difday = None
        if len(x) == 0: return
        self._difday = int(x[1:])

    # ----------------------
    def _decode_333_4FFFF(self, x):
        self._sensday = None
        if len(x) == 0: return
        self._sensday = int(x[1:])

    # ----------------------
    def _decode_333_553SS(self, x):
        self._sun = None
        if len(x) == 0: return
        # Convert to minutes (what's delivered by BUFR)
        if not x[3:] == "//":
            self._sun = int(x[3:]) * 360 #/ 10 * 3600

    # ----------------------
    def _decode_333_6RRRt(self, x):
        if len(x) == 0: return

    # ----------------------
    def _decode_333_7RRRR(self, x):
        if len(x) == 0: return

    # ----------------------
    def _decode_333_89blocks(self, x):
        self._ffx     = None
        self._ffmin6  = None
        self._ffmean6 = None
        self._ffmax6  = None
        self._ff6     = None
        self._ffx6    = None
        if len(x) == 0: return
        tmp = self.regex89.findall(x)
        if len(tmp[0]) == 0: return

        # Only decoding wind for now
        # 910ff -- Hoechste Windspitze in den letzten 10 Minuten (> 12,5 m/s)
        # 911ff -- Hoechste Windspitze seit dem letzten synoptischen Haupttermin (> 12,5 m/s)
        # 912ff -- Hoechstes 10-Minuten-Mittel der Windgeschwindigkeit
        #          seit dem letzten synoptischen Haupttermin (> 10,5 m/s)
        for x in tmp:
            if self._knots is None:
                raise Exception("YYGGggi did not provide any wind speed units, but now " + \
                        "wind speed in {:s} has been found! That's not good. Stop.".format(x[:3]))
            if x[:3] == "910":
                self._ffx = int(x[3:]) * 10
                if self._knots:
                    self._ffx = int(float(self._ffx) * 0.5144447)
            elif x[:3] == "911":
                self._ffx6 = int(x[3:]) * 10
                if self._knots:
                    self._ffx6 = int(float(self._ffx6) * 0.5144447)
            elif x[:3] == "912":
                self._ffmax6 = int(x[3:]) * 10
                if self._knots:
                    self._ffmax6  = int(float(self._ffmax6) * 0.5144447)
            elif x[:3] == "913":
                self._ffmean6 = int(x[3:]) * 10
                if self._knots:
                    self._ffmean6  = int(float(self._ffmean6) * 0.5144447)
            elif x[:3] == "914":
                self._ffmin6 = int(x[3:]) * 10
                if self._knots:
                    self._ffmin6  = int(float(self._ffmin6) * 0.5144447)



    def get(self, key):
        """get(key)

        Parameters
        ----------
        key : str
            the attribute of the object which should be returned

        Returns
        -------
        In this case: return the value of the attribute if existing,
        else None will be returned.
        """

        if not hasattr(self, "_{:s}".format(key)):
            return None
        else:
            return getattr(self, "_{:s}".format(key))



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
if __name__ == "__main__":

    import argparse
    # Parsing input args
    parser = argparse.ArgumentParser(description="Download some IHD observation data")
    parser.add_argument("--station", "-s", type = int, default = 11120,
               help = "Number of the station to be processes.")
    parser.add_argument("--testfile", type = str, default = None,
               help = "Process this one test file (development).")
    parser.add_argument("--latest", "-l", type = int, default = None,
               help = "For operational use, loads the latest N (input latest, int) days only.")
    parser.add_argument("--devel", default = False, action = "store_true",
               help = "Used for development. If set, the script reads config_devel.conf" + \
                      " instead of config.conf.")
    args = vars(parser.parse_args())

    import sys
    import os
    import re
    import numpy as np
    import datetime as dt

    # Reading config file
    config = read_obs_config("config.conf")
    if not os.path.isdir(config.get("isddir")):
        try:
            os.makedirs(config.get("isddir"))
        except Exception as e:
            raise Exception(e)

    if args["testfile"]:
        print("Reading {:s}".format(args["testfile"]))
        messages = get_synop_messages(args["testfile"])
        sys.exit(" --- development stop (--testfile) ---- ")

    # The year ...
    for year in range(2014, int(dt.date.today().strftime("%Y")) + 1):

        for mon in range(1, 13):

            # If this year/month is in the future: stop.
            if not args["latest"]:
                if year == int(dt.date.today().strftime("%Y")) and  \
                   mon > int(dt.date.today().strftime("%m")):
                    print("[!] Stop here, reached current month/year")
                    break

                bgn = dt.datetime(year, mon, 1, 0, 0, 0)
                end = dt.datetime(year + 1 if mon == 12 else year,
                                  1 if mon == 12 else mon + 1, 1, 0, 0)

                # Generate URL and local file name
                synfile = os.path.join(config.get("htmldir"),
                          "ogimet_synop_{:d}_{:04d}_{:02d}.dat".format(
                          args["station"], year, mon))
            else:
                end = dt.datetime.now()
                bgn = dt.datetime.now() - dt.timedelta(args["latest"])
                synfile = os.path.join(config.get("htmldir"),
                          "ogimet_latest_{:d}.dat".format(args["station"]))

            # URL for data download
            url = "http://www.ogimet.com/cgi-bin/getsynop" + \
                    "?begin={:s}".format(bgn.strftime("%Y%m%d%H%M")) + \
                    "&end={:s}".format(end.strftime("%Y%m%d%H%M")) + \
                    "&block={:05d}".format(args["station"])
    
            # Download file if required
            if not os.path.isfile(synfile):
                print("Downloading data from OGIMET CGI")
                if not args["latest"]:
                    print("  - Year/Month {:d}/{:02d}, station {:d}".format(year, mon, args["station"]))
                else:
                    print("  - Latest {:d} days for {:d}".format(args["latest"], args["station"]))
                print("  - URL: {:s}".format(url))

                import urllib2
                import time
                counter = 0
                while counter < 10:

                    ++counter;
    
                    uid = urllib2.urlopen(url)
                    content = uid.readlines()
                    if len(content) == 0:
                        print("    No data for this request, create empy file")
                        fid = open(synfile, "w")
                        fid.close()
                        break;
                    uid.close()
                    # If we overstressed ogimet: do not save, sleep 1 minute,
                    # and try again.
                    if re.match("Status: 501 Sorry", content[0]):
                        print("    Hoppala, overstressed ogimet ... sleep a while and retry")
                        time.sleep(120)
                    else: 
                        fid = open(synfile, "w")
                        fid.write("".join(content))
                        fid.close()
                        if args["latest"] is None:
                            print("    Just being nice to ogimet, sleep a bit ...")
                            time.sleep(60)
                        break;
    
            print("Reading {:s}".format(synfile))
            messages = get_synop_messages(synfile, verbose = False)
    


            # For database: generate a column vector and fetch data
            colnames = ["datumsec", "T", "Td", "Tmin12", "Tmax12",
                        "p", "pmsl", "pch", "ptend",
                        "rr6", "rr12", "rr24",
                        "VV", "ww", "W1", "W2", "sun", "sunday", "N",
                        "dd", "ff", "ffx", "ffmin6", "ffmean6", "ffmax6", "ff6", "ffx6"]
            data = []
            for rec in messages():
                data.append(rec.get_tuple(colnames))


            # Development output
            if not args["latest"]:
                show_tab(colnames, data)#, n = 5)
            else:
                show_tab(colnames, data)

            # Define and open sqlite3 database
            sql3file = "obs_{:d}.sqlite3".format(args["station"])
            db = obs_db(config.get("sqlite3dir"), sql3file, colnames)
    
            db.write(colnames, data)
        
            # If only latest was requested, stop here.
            if args["latest"]:
                from os import remove
                remove(synfile)
                sys.exit(0)























