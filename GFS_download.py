#!/usr/bin/python
# -------------------------------------------------------------------
# - NAME:        GEFS.py
# - AUTHOR:      Reto Stauffer
# - DATE:        2018-10-11
# -------------------------------------------------------------------
# - DESCRIPTION: Quick and dirty py2.7 script to download some data
#                for delta airlines. Requires wgrib2 for the spatial
#                subsetting. 
# -------------------------------------------------------------------
# - EDITORIAL:   2018-10-11, RS: Created file on thinkreto.
# -------------------------------------------------------------------
# - L@ST MODIFIED: 2018-11-01 19:04 on pc24-c707
# -------------------------------------------------------------------

# -------------------------------------------------------------------
# -------------------------------------------------------------------
def bar():
    """bar()

    Simply prints a line of "-" on stdout.
    """
    print("{:s}".format("".join(["-"]*70)))

# -------------------------------------------------------------------
# -------------------------------------------------------------------
def get_remote_file_names(baseurl, date, step):
    """get_file_names(baseurl, date, step)

    Generates the file names (remote only)

    Parameters
    ----------
    baseurl : str
        base url, used to format the data (can contain %Y%m%d or similar)
    date : datetime.datetime
        defines model initialization date and time
    step : int
        forecast step (in hours)

    Returns
    -------
    Returns a dict with two entries for the inventory file or index file ("idx")
    and the grib file ("grib")
    """
    import os
    import datetime as dt
    if not isinstance(step, int):
        raise ValueError("step has to be an integer (get_remote_file_names function)")

    # Create URL
    fileurl  = os.path.join(date.strftime(baseurl), "gfs_4_{:s}_{:s}_{:03d}".format(
                            date.strftime("%Y%m%d"), date.strftime("%H%M"), step)) 
    return {"grib"   : "{:s}.grb2".format(fileurl),
            "idx"    : "{:s}.inv".format(fileurl)}


def get_local_file_names(filedir, date, shortName, step):
    """get_file_names(filedir, baseurl, date, step)

    Generates the file names (remote only)

    Parameters
    ----------
    filedir : str
        name of the directory where to create the file "local"
    date : datetime.datetime
        defines model initialization date and time
    shortName : str
        shorntame of the parameter for local file naming.
    step : int
        forecast step (in hours)

    Returns
    -------
    Returns a dict with two entries. "local" is the local file when downloading
    the whole globe, "subset" the file name after subsetting (only if subsetting
    is required).
    """
    if not isinstance(shortName, str):
        raise ValueError("shortName must be a string (get_local_file_names function)")
    if not isinstance(step, int):
        raise ValueError("step must be an integer (get_local_file_names function)")

    local    = date.strftime("GFS_%Y%m%d_%H00") + "_f{:03d}_{:s}.grb2".format(step, shortName)
    subset   = date.strftime("GFS_%Y%m%d_%H00") + "_f{:03d}_{:s}_subset.grb2".format(step, shortName)

    from os.path import join
    return {"local": join(filedir, local), "subset": join(filedir, subset)}


# -------------------------------------------------------------------
# -------------------------------------------------------------------
class idx_entry(object):
    def __init__(self, args):
        """idx_entry(args)

        A small helper class to handle index entries.
        
        Parameters
        ----------
        args : list
            list with three entries (bytes start, param name, param level)
        """
        self._byte_start = int(args[0])
        self._var        = str(args[1])
        self._lev        = str(args[2])
        self._byte_end   = False

    def add_end_byte(self, x):
        """add_end_byte(x)

        Appends the ending byte.
        """
        self._byte_end = x

    def end_byte(self):
        """end_byte()

        Returns end byte.
        """
        try:
            x = getattr(self, "_byte_end")
        except:
            raise Error("whoops, _byte_end attribute not found.")
        return x 

    def start_byte(self):
        """start_byte()

        Returns start byte.
        """
        try:
            x = getattr(self, "_byte_start")
        except:
            raise Error("whoops, _byte_start attribute not found.")
        return x 

    def key(self):
        """key()

        Returns
        -------
        Returns a character string "<param name>:<param level>".
        """
        try:
            var = getattr(self, "_var")
            lev = getattr(self, "_lev")
        except Exception as e:
            raise Exception(e)

        return "{:s}:{:s}".format(var,lev)

    def range(self):
        """range()

        Returns
        -------
        Returns the byte range for curl.
        """
        try:
            start = getattr(self, "_byte_start")
            end   = getattr(self, "_byte_end")
        except Exception as e:
            raise Exception(e)
        end = "" if end is None else "{:d}".format(end)

        return "{:d}-{:s}".format(start, end)

    def __repr__(self):
        if isinstance(self._byte_end, bool):
            end = "UNKNOWN"
        elif self._byte_end is None:
            end = "end of file"
        else:
            end = "{:d}".format(self._byte_end)
        return "IDX ENTRY: {:10d}-{:>10s}, '{:s}'".format(self._byte_start,
                end, self.key())

# -------------------------------------------------------------------
# -------------------------------------------------------------------
def parse_index_file(idxfile):
    """parse_index_file(idxfile)
 
    Downloading and parsing the grib index file.

    Parameters
    ----------
    idxfile : str
        url to the index file

    Returns
    -------
    Returns a list of index entries (entries of class idx_entry).
    """

    import urllib2
    try:
        req  = urllib2.Request(idxfile)
        data = urllib2.urlopen(req).read().split("\n")
    except Exception as e:
        print("[!] Problems reading index file\n    {:s}\n    ... return None".format(idxfile))
        return None

    # List to store the required index message information
    idx_entries = []

    # Parsing data (extracting message starting byte,
    # variable name, and variable level)
    import re
    comp = re.compile("^\d+:(\d+):d=\d{10}:([^:.*]*):([^:.*]*)")
    byte = 1 # initial byte
    for line in data:
        if len(line) == 0: continue
        mtch = re.findall(comp, line)
        if not mtch:
            raise Exception("whoops, pattern mismatch \"{:s}\"".format(line))
        # Else crate the variable hash
        idx_entries.append(idx_entry(mtch[0]))

    # Now we know where the message start (bytes), but we do not
    # know where they end. Append this information.
    for k in range(0, len(idx_entries)):
        if (k + 1) == len(idx_entries):
            idx_entries[k].add_end_byte(None)
        else:
            idx_entries[k].add_end_byte(idx_entries[k+1].start_byte() - 1)

    # Go trough the entries to find the messages we request for.
    return idx_entries

def get_required_bytes(idx, params):
    """get_required_bytes(idx, params)

    Searching for the entries in idx corresponding to the parameter
    definition in params (has to match the grib2 inventory param names, e.g.,
    "TMP:2 m surface"). Returns a list of bytes which have to be downloaded
    with curl later on.

    Parameter
    ---------
    idx : list
        list of idx_entry objects. The list returned by parse_index_file.
    params : str or list
        names of the parameters for which the data should be downloaded later on.
        Can be a single string or a list of strings.

    Returns
    -------
    Returns a list of bytes (for curl).
    """

    # Crate a list of the string if only one string is given.
    if isinstance(params, str): params = [params]
    if not isinstance(params, list):
        raise ValueError("params has to be a single string or a list (in get_rquired_bytes)")

    # Go trough the entries to find the messages we request for.
    res = []
    for x in idx:
        if x.key() in params: res.append(x.range())
        
    # Return ranges to be downloaded
    return res

# -------------------------------------------------------------------
def download_range(grib, local, range):
    import urllib2
    print("- Downloading data for {:s}".format(local))
    try:
        req = urllib2.Request(grib)
        req.add_header("Range", "bytes={:s}".format(",".join(range)))
        resp = urllib2.urlopen(req)
    except:
        print("[!] Problems downloading the data.\n    Return None, trying to continue ...")
        import sys
        sys.exit(3)
        return None

    with open(local, "wb") as fid: fid.write(resp.read())
    return True


# -------------------------------------------------------------------
# Main script
# -------------------------------------------------------------------
if __name__ == "__main__":

    # Config
    outdir = "data"
    baseurl = "https://nomads.ncdc.noaa.gov/data/gfs4/%Y%m/%Y%m%d/"
    # Subset (requires wgrib2), can also be None.
    # Else a dict with N/S/E/W in degrees (0-360!)
    subset = {"W": 5, "E": 18, "S": 45, "N": 55}

    # Time to sleep between two requests
    import time
    sleeping_time = 5;

    # List of the required parameters. Check the index file
    # to see the available parameters. Always <param>:<level> where
    # <param> and <level> are the strings as in the grib index file.
    import ConfigParser
    CNF = ConfigParser.ConfigParser()
    CNF.read("config.conf")
    params = {}
    for rec in CNF.items("params"): params[rec[0]] = rec[1]

    # Import some required packages
    import sys, os, re
    import argparse, sys
    import datetime as dt
    import numpy as np
    import distutils.spawn
    import subprocess as sub

    # Parsing input args
    parser = argparse.ArgumentParser(description="Download some GEFS data")
    parser.add_argument("--date","-d", type = str,
               help = "Model initialization date. Format has to be YYYY-mm-dd!" + \
                      " Date has to be 2016-12-01 and after. No data before this point.")
    parser.add_argument("--runhour","-r", type = int,
               help = "Model initialization hour, 0/6/12/18, integer.")
    args = vars(parser.parse_args())

    # Checking args
    if args["runhour"] is None or args["date"] is None:
        parser.print_usage(); sys.exit(9)
    if not re.match("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", args["date"]):
        parser.print_usage()
        raise ValueError("wrong format for input -d/--date")
    if not args["runhour"] in [0, 6, 12, 18]:
        parser.print_usage()
        raise ValueError("wrong input for -r/--runhour, has to be 0/6/12/18")

    # Crate date arg
    date   = dt.datetime.strptime("{:s} {:02d}:00".format(args["date"], args["runhour"]),
                                  "%Y-%m-%d %H:%M")
    # Too old?
    if date < dt.datetime(2016, 12, 1, 0, 0):
        parser.print_usage()
        raise ValueError("Sorry, no data before 2016-12-01")

    # Steps/members. The +1 is required to get the required sequence!
    steps   = np.arange(18, 84+1, 3, dtype = int)

    bar()
    print("Downloading steps:\n  {:s}".format(", ".join(["{:d}".format(x) for x in steps])))
    print("For date/model initialization\n  {:s}".format(date.strftime("%Y-%m-%d %H:%M UTC")))
    print("Base url:\n  {:s}".format(date.strftime(baseurl)))
    bar()

    # Specify and create output directory if necessary
    filedir = "{:s}/{:s}".format(outdir, date.strftime("%Y%m%d%H%M"))
    if not os.path.isdir(filedir):
        try:
            os.makedirs(filedir)
        except:
            raise Exception("Cannot create directory {:s}!".format(filedir))

    # Looping over the different members first
    # Looping over forecast lead times
    for step in steps:
        bar()
        print("Processing +{:03d}h forecast".format(step))
        bar()

        # Generate remote file URL's
        remote_files = get_remote_file_names(baseurl, date, step)
        # Read index file (once per forecast step as the file changes
        # with forecast step).
        idx = parse_index_file(remote_files["idx"])

        # Looping over short names
        for shortName,param in params.iteritems():

            print("Checking/downloading {:s} ({:s})".format(param, shortName))

            # Local file names
            files = get_local_file_names(filedir, date, shortName, step)

            # Getting file names
            if os.path.isfile(files["subset"]):
                print("- Local subset exists, skip")
                bar()
                continue
            if os.path.isfile(files["local"]):
                print("- Local file exists, skip")
                bar()
                continue

            # Read/parse index file (if possible)
            required = get_required_bytes(idx, param)

            # If no messages found: continue
            if required is None: continue
            if len(required) == 0: continue

            # Downloading the data
            download_range(remote_files["grib"], files["local"], required)

            # If wgrib2 exists: crate subset (small_grib)
            check = distutils.spawn.find_executable("wgrib2")
            if not check is None and not subset is None:
                WE  = "{:.2f}:{:.2f}".format(subset["W"], subset["E"])
                SN  = "{:.2f}:{:.2f}".format(subset["S"], subset["N"])
                cmd = ["wgrib2", files["local"], "-small_grib", WE, SN, files["subset"]] 
                print("- Subsetting: {:s}".format(" ".join(cmd)))
                p = sub.Popen(cmd, stdout = sub.PIPE, stderr = sub.PIPE) 
                out,err = p.communicate()

                if p.returncode == 0:
                    print("- Subset created, delete global file")
                    os.remove(files["local"])
                else:
                    print("[!] Problem with subset, do not delete global grib2 file.")


            # Else post-processing the data
            bar()

            print("Sleeping {:d} seconds ...".format(sleeping_time))
            time.sleep(sleeping_time)
























