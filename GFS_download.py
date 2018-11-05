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
# - L@ST MODIFIED: 2018-11-05 09:31 on marvin
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
def get_file_names(config, date, step, filedir):
    """get_file_names(config, date, step, filedir)

    Generates the file names (remote only)

    Parameters
    ----------
    config : read_config object
        the object returned by "read_config"
    baseurlrolling : str
        base url for the rolling archive (can contain %Y%m%d or similar)
    date : datetime.datetime
        defines model initialization date and time
    step : int
        forecast step (in hours)
    filedir : str
        folder where to store the downloaded files

    Returns
    -------
    Returns a dict with two entries for the inventory file or index file ("idx")
    and the grib file ("grib") plus a local file name ("local") and the file
    name of the local subset ("subset").
    """
    from os.path import join
    import datetime as dt
    if not isinstance(filedir, str):
        raise ValueError("filedir has to be a string (get_file_names function)")
    if not isinstance(step, int):
        raise ValueError("step has to be an integer (get_file_names function)")

    # If forecast run is not older than 5 days
    today = dt.datetime.today()
    if ((today - date).total_seconds() / 86400) < 5:
        baseurl = date.strftime(config.get("rolling_url"))
        grburl  = date.strftime(config.get("rolling_grb")).replace("<step>", "{:03d}".format(step))
        idxurl  = date.strftime(config.get("rolling_idx")).replace("<step>", "{:03d}".format(step))
    else:
        baseurl = date.strftime(config.get("archive_url"))
        grburl  = date.strftime(config.get("archive_grb")).replace("<step>", "{:03d}".format(step))
        idxurl  = date.strftime(config.get("archive_idx")).replace("<step>", "{:03d}".format(step))

    # Local file names
    local    = date.strftime("GFS_full_%Y%m%d_%H00") + "_f{:03d}.grb2".format(step)
    subset   = date.strftime("GFS_full_%Y%m%d_%H00") + "_f{:03d}_subset.grb2".format(step)

    files = {"grib"   : join(baseurl, grburl),
             "idx"    : join(baseurl, idxurl),
             "local"  : join(filedir, local),
             "subset" : join(filedir, subset)}
    for key,val in files.iteritems():
        print(" - {:<10s} {:s}".format(key, val))

    return files


# -------------------------------------------------------------------
# -------------------------------------------------------------------
def get_param_file_name(filedir, date, step, param):
    """get_param_file_name(filedir, date, step, param)

    Generates the parameter-based file name.

    Parameters
    ----------
    filedir : str
        folder where to store the downloaded files
    date : datetime.datetime
        defines model initialization date and time
    step : int
        forecast step (in hours)
    param : str
        shortname of the parameter

    Returns
    -------
    Returns a string, file name of the local parameter-based file.
    This is used to check if the files exist and to split the "full" grib file
    into single parameter-based grib files.
    """
    import os
    import datetime as dt
    if not isinstance(filedir, str):
        raise ValueError("filedir has to be a string")
    if not isinstance(step, int):
        raise ValueError("step has to be an integer")
    if not isinstance(param, str):
        raise ValueError("param has to be a string")

    # Local file names
    tmp = date.strftime("GFS_%Y%m%d_%H00")
    return {"local"  : os.path.join(filedir, "{:s}_f{:03d}_{:s}.grb2".format(tmp, step, param)),
            "subset" : os.path.join(filedir, "{:s}_f{:03d}_{:s}_subset.grb2".format(tmp, step, param))}


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

        mtch = re.search("^([0-9]+)-([0-9]+)$", args[3])
        if mtch:
            self._step = int(mtch.group(2))
        else:
            self._step = int(args[3])

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

    def step(self):
        """step()

        Returns
        -------
        Message forecast step.
        """
        return self._step

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
        return "IDX ENTRY: {:10d}-{:>10s}, '{:s}' (+{:d}h)".format(self._byte_start,
                end, self.key(), self.step())

# -------------------------------------------------------------------
# -------------------------------------------------------------------
def parse_index_file(idxfile, remote = True):
    """parse_index_file(idxfile, remote = True)
 
    Downloading and parsing the grib index file.
    Can be used to read local and remote (http/https) index files.

    Parameters
    ----------
    idxfile : str
        url to the index file
    remote : bool
        if remote = True urllib2 is used to read the file from the
        web, else expected to be a local file.

    Returns
    -------
    Returns a list of index entries (entries of class idx_entry).
    """

    if remote:
        import urllib2
        try:
            req  = urllib2.Request(idxfile)
            data = urllib2.urlopen(req).read()
        except Exception as e:
            print("[!] Problems reading index file\n    {:s}\n    ... return None".format(idxfile))
            return None
        # If the file is empty
        if len("".join(data)) == 0:
            print("[!] Problems reading index file, was emptu")
            return None
    else:
        from os.path import isfile
        if not isfile(idxfile):
            raise Exception("file {:s} does ont exist on disc".format(idxfile))
        with open(idxfile, "r") as fid:
            data = "".join(fid.readlines())

    if len(data) == 0:  return None
    else:               data = data.split("\n")
       

    # List to store the required index message information
    idx_entries = []

    # Parsing data (extracting message starting byte,
    # variable name, and variable level)
    import re
    #                       hour            param     level     step
    comp = re.compile("^\d+:(\d+):d=\d{10}:([^:.?]+):([^:\\..?]*):([0-9-]+)\shour\s([a-z]+\s)?fcst.*$")
    byte = 1 # initial byte
    for line in data:
        if len(line) == 0: continue
        mtch = re.findall(comp, line.replace(".", "-"))
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


# -------------------------------------------------------------------
# -------------------------------------------------------------------
def create_index_file(grbfile):
    """parse_index_file(grbfile):
 
    Well, this is not very efficient. If I cannot find the index file
    on the server (happens every now and then) I am simply downloading
    the grib2 file if existing, create my own index file, and use
    this index file. However, at this point I already have a local
    copy of the grib2 file and I could use this rather than downloading
    via curl once again. But ... TODO.

    Parameters
    ----------
    grbfile : str
        url of the remote grib2 file.

    Returns
    -------
    Either None if the grib2 file does not exist (in this case we
    cannot create an index file locally) or what parse_index_file returns.
    """

    # Requires wgrib2: check if existing
    import distutils.spawn
    check = distutils.spawn.find_executable("wgrib2")
    if not check: 
        print("[!] Creating index file on your own does not work (wgrib2 missing), skip.")
        return None

    # Import library
    try:
        from urllib import urlretrieve # Python 2
    except ImportError:
        from urllib.request import urlretrieve # Python 3

    import tempfile
    tmp1 = tempfile.NamedTemporaryFile(prefix = "GFS_grib_")
    tmp2 = tempfile.NamedTemporaryFile(prefix = "GFS_idx_")
    try:
        urlretrieve(grbfile, tmp1.name)
    except:
        return None
    
    import subprocess as sub
    import os
    print(tmp1.name)
    print(grbfile)
    os.system("wgrib2 {:s}".format(tmp1.name))
    p = sub.Popen(["wgrib2", tmp1.name],
                  stdout = sub.PIPE, stderr = sub.PIPE)
    out, err = p.communicate()

    if not p.returncode == 0:
        print("[!] Not able to create proper index file in create_index_file, return None")
        return None

    with open(tmp2.name, "w") as fid: fid.write(out)

    idx = parse_index_file(tmp2.name, remote = False)
    tmp1.close()
    tmp2.close()
      
    # Return list
    return idx



# -------------------------------------------------------------------
# -------------------------------------------------------------------
def get_required_bytes(idx, params, step, stopifnot = False):
    """get_required_bytes(idx, params, step, stopifnot = False)

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
    step : int
        forecast step
    stopifnot : bool
        stop if one (or several) parameters cannot be found in the index
        file. If set to false these messages will simply be ignored.

    Returns
    -------
    Returns a list of bytes (for curl).
    """

    # Crate a list of the string if only one string is given.
    if isinstance(params, str): params = [params]
    if not isinstance(params, list):
        raise ValueError("params has to be a single string or a list")
    if not isinstance(step, int):
        raise ValueError("step has to be of tyep int")

    # Go trough the entries to find the messages we request for.
    res = []
    found = []
    for x in idx:
        if not x.step() == step: next
        if x.key() in params:
            res.append(x.range())
            found.append(x.key())

    missing = []
    for rec in params:
        if not rec in found:
            missing.append(rec)
    if len(missing) > 0:
        print("[!] Could not find: {:s}".format(", ".join(missing)))
        if stopifnot: raise Exception("Some parameters not found in index file! Check config.")
        
    # Return ranges to be downloaded
    return res

# -------------------------------------------------------------------
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
# -------------------------------------------------------------------
class read_config():

    def __init__(self, file, paramset = None):
        """read_config(file)

        Reading the required configuration from the config file.

        Parameters
        ----------
        file : str
            name/path of the configuration file
        paramset : None or str
            if None the [param] config will be read, else the
            [param <set>] config is parsed from the config file. Allowes
            to process different sets of parameters with the same script.

        Returns
        -------
        No return, initializes a new class of type mos_config with a set
        of arguments used to download/process the GFS forecasts.
        """

        self.paramset = paramset
        self.file = [] # Used to store the config file names
        self.read(file, paramset = paramset)

    def get(self, key):
        """get(key)

        Returns attribute \"key\" from the object. If not found,
        a ValueError will be raised.

        Parameter
        ---------
        key : str
            name of the attribute

        Returns
        -------
        Returns the value of the attribute from the object if existing,
        else a ValuerError will be raised.
        """
        if not hasattr(self, key):
            raise ValueError("read_config has no attribute \"{:s}\"".format(key))
        return getattr(self, key)

    def __repr__(self):

        res = "GFS Configuration:\n"
        res += "   Config read from (seq):    {:s}\n".format(", ".join(self.file))
        res += "   Number of parameters:      {:d}\n".format(len(self.params))
        res += "   Forecast steps:            {:s}\n".format(", ".join([str(x) for x in self.steps]))
        res += "   Where to store grib files: {:s}\n".format(self.gribdir)
        return(res)

    def read(self, file, paramset = None):

        if not isinstance(file, str):
            raise ValueError("input \"file\" has to be a string (read_param_config method)")
        from os.path import isfile
        if not isfile(file):
            raise ValueError("the file file=\"{:s}\" does not exist".format(file))
                
        # Read parameter configuration.
        import ConfigParser
        CNF = ConfigParser.ConfigParser()
        CNF.read(file)

        # Append file
        self.file.append(file)
        self._read_params(CNF)
        self._read_steps(CNF)
        self._read_gribdir(CNF)
        self._read_gfs_urls(CNF)

        # If one of the required items is missing: stop
        for key in ["file", "params", "steps", "gribdir", \
                "archive_url", "archive_grb", "archive_idx",
                "rolling_url", "rolling_grb", "rolling_idx"]:
            if not hasattr(self, key):
                raise Exception("have not found proper \"{:s}\" definition in config file.".format(key))


    def _read_gfs_urls(self, CNF):
        # GFS archive server
        try:
            self.archive_url = CNF.get("gfs", "archive_url")
        except:
            pass
        try:
            self.archive_grb = CNF.get("gfs", "archive_grb")
        except:
            pass
        try:
            self.archive_idx = CNF.get("gfs", "archive_idx")
        except:
            pass
        # Live rolling GFS server distribution system
        try:
            self.rolling_url = CNF.get("gfs", "rolling_url")
        except:
            pass
        try:
            self.rolling_grb = CNF.get("gfs", "rolling_grb")
        except:
            pass
        try:
            self.rolling_idx = CNF.get("gfs", "rolling_idx")
        except:
            pass


    def _read_gribdir(self, CNF):
        try:
            self.gribdir = CNF.get("main", "gribdir")
        except:
            return

    def _read_params(self, CNF):

        # If not yet set: create a new dictionary
        if not hasattr(self, "params"): self.params = {}
        section = "params" if not self.paramset else "params %s".format(self.paramset)
        try:
            for rec in CNF.items(section): self.params[rec[0]] = rec[1].replace(".", "-")
        except:
            return

    def _read_steps(self, CNF):

        try:
            steps = CNF.get("main", "steps")
        except:
            return

        # Trying to decode the user value
        import re
        if re.match("^[0-9]+$", steps):
            self.steps = [int(steps)]
        elif re.match("^[0-9,\s]+$", steps):
            self.steps = [int(x.strip()) for x in steps.split(",")] 
            self.steps = list(np.unique(self.steps))
        elif re.match("^[0-9]+/to/[0-9]+/by/[0-9]+$", steps):
            tmp = re.findall("([0-9]+)/to/([0-9]+)/by/([0-9]+)$", steps)[0]
            self.steps = list(np.arange(int(tmp[0]), int(tmp[1])+1, int(tmp[2]), dtype = int))
        else:
            raise Exception("misspecified option \"steps\" in [main] config section.")
 


# -------------------------------------------------------------------
# -------------------------------------------------------------------
def check_files_exist(files, params, subset_files, split_files):
    """check_files_exist(files, params, subset_files, split_files)

    This function checks the existance of local files to see whether
    the download has been done already and whether or not all required
    information is available on the local disc. If so, we do not have
    to download the files again.

    Note that there is a split_files option. If split_files is false
    we are only checking if the "full" grib file (subset) is available.
    In this case we do _not_ check if the file does contain all the
    required parameters!

    In case split_files is true this method is checking whether or not
    all parameter-based files are avilable on the local machine. If not,
    a False will be returned such that we can run the download again.

    Parameters
    ----------
    files : dict
        contains the remote and local file snames of the "full"
        (not split into parameter-dependent grib files) file names.
        This is what has been returned by get_file_names(...).
    params : dict
        dictionary containing the GFS parameter specifications
        and the local short name, this is what has been returned
        by read_param_config(...)
    subset_files : bool
        flag whether subsetting is enabled or disabled. If true
        we are looking for the *subset.grb2 files, else for the
        non-subsetted ones.
    split_files : bool
        the split_files option. If false we are only checking
        if the "full" grib file is available on disc, else
        we are looping trough the parameters and check if
        all parameters are already on disc.

    Returns
    -------
    """

    if not isinstance(split_files, bool):
        raise ValueError("split_files has to be boolean")
    if not isinstance(subset_files, bool):
        raise ValueError("subset_files has to be boolean")

    import os
    # Only check the "full" file
    if not split_files:
        # If the subset file does not exist: return False
        if subset_files:
            if not os.path.isfile(files["subset"]):   return False
            else:                                     return True
        else:
            if not os.path.isfile(files["local"]):    return False
            else:                                     return True
    # Else we have to check all single files
    else:
        for rec in params.iteritems():
            tmp = get_param_file_name(filedir, date, step, rec[0])
            if subset_files:
                if not os.path.isfile(tmp["subset"]):
                    return False # At least one missing!
            else:
                if not os.path.isfile(tmp["local"]):
                    return False # At least one missing!

        # If we were able to reach this point all files are here,
        # return True.
        return True


# -------------------------------------------------------------------
# -------------------------------------------------------------------
def split_grib_file(gribfile, filedir, date, step, params, delete = True):
    """split_grib_file(gribfile, filedir, date, step, params)

    Split grib file into parameter-based grib files.

    Parameter
    ---------
    TODO
    """
    # Generate index file first
    import tempfile
    tmp = tempfile.NamedTemporaryFile(prefix = "GFS_downloader_")

    # Create grib2 inventory of local file
    cmd = ["wgrib2", gribfile]
    p = sub.Popen(cmd, stdout = sub.PIPE, stderr = sub.PIPE) 
    out,err = p.communicate()
    if not p.returncode == 0:
        print(err)
        raise Exception("problems creating the index file with wgrib2!")
    else:
        tmp.write(out)
        tmp.flush()

    # Parse new inventory
    idx = parse_index_file(tmp.name, False)
    tmp.close()

    # Split file into parameter-specific grib files
    gfs_params = [x.key() for x in idx]
    for shortName,param in params.iteritems():
        k = [i for i,x in enumerate(gfs_params) if x == param]
        if not len(k) == 1:
            raise Exception("cannot find a specific parameter in the index file .. hmm.")

        # Write this specific message into a new file
        outfile = get_param_file_name(filedir, date, step, shortName)
        cmd = ["wgrib2", files["local"] if subset is None else files["subset"],
                "-d", "{:d}".format(1 + k[0]), "-grib",
                outfile["local"] if subset is None else outfile["subset"]]
        p = sub.Popen(cmd, stdout = sub.PIPE, stderr = sub.PIPE)
        out, err = p.communicate()
        if not p.returncode == 0:
            raise Exception(err)

    os.remove(gribfile)

# -------------------------------------------------------------------
# Main script
# -------------------------------------------------------------------
if __name__ == "__main__":

    # Config
    outdir = "data"
    # Subset (requires wgrib2), can also be None.
    # Else a dict with N/S/E/W in degrees (0-360!)
    subset = {"W": 5, "E": 18, "S": 45, "N": 55}

    # Time to sleep between two requests
    import time
    sleeping_time = 2;

    # Split files into parameter-based files?
    split_files = True

    # List of the required parameters. Check the index file
    # to see the available parameters. Always <param>:<level> where
    # <param> and <level> are the strings as in the grib index file.
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
    parser.add_argument("--set","-s", type = str, default = None,
               help = "Which set of parameters should be downloaded? Default is None, " + \
                      "reading [param] config. However, this allows you to set up multiple " + \
                      "sets of parameters in the config file if needed.")
    parser.add_argument("--runhour","-r", type = int,
               help = "Model initialization hour, 0/6/12/18, integer.")
    parser.add_argument("--devel", default = False, action = "store_true",
               help = "Used for development. If set, the script reads config_devel.conf" + \
                      " instead of config.conf.")
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

    # Reading parameter configuration
    config = read_config("config.conf", args["set"])
    if args["devel"]: config.read("devel.conf")

    bar(); print config; bar()

    # Specify and create output directory if necessary
    filedir = "{:s}/{:s}".format(config.gribdir, date.strftime("%Y%m%d%H%M"))
    if not os.path.isdir(filedir):
        try:
            os.makedirs(filedir)
        except:
            raise Exception("Cannot create directory {:s}!".format(filedir))


    # Looping over the different members first
    # Looping over forecast lead times
    for step in config.steps:
        print("Processing +{:03d}h forecast".format(step))

        # Generate remote file URL's
        files = get_file_names(config, date, step, filedir)

        # Check if all files exist. If so, we can skip this download.
        file_check = check_files_exist(files, config.params, not subset is None, split_files)
        if file_check: 
            print("All files on disc, continue ...")
            continue

        # Read index file (once per forecast step as the file changes
        # with forecast step).
        idx = parse_index_file(files["idx"])
        if idx is None:
            print("Create local index file, as index file does not exist!")
            idx = create_index_file(files["grib"])

        # File is empty?
        if idx is None:
            print("Not able to download/parse the index file. Possible reason:")
            print("problems with internet/server or the forecast is not available.")
            print("Continue and skip this one ...")
            continue

        # List of the GFS parameter names, used to check what
        # to download based on the inventory or index file.
        gfs_params = [x[1] for x in config.params.iteritems()]

        # Read/parse index file (if possible) and identify the
        # required sections (byte-sections) for curl download.
        required = get_required_bytes(idx, gfs_params, step, True)

        # If no messages found: continue
        if required is None:
            print("Could not find any required fields, skip ...")
            continue
        if len(required) == 0:
            print("Could not find any required fields, skip ...")
            continue

        # If wgrib2 exists: used to subset the grib file (-small_grib) and
        # to create the index file is split_files is set to True.
        check = distutils.spawn.find_executable("wgrib2")

        # Downloading the data
        download_range(files["grib"], files["local"], required)

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
                raise Exception("Problem with subset, do not delete global grib2 file.")

        # Split file
        if not check is None and split_files:
            split_grib_file(files["local"] if subset is None else files["subset"],
                            filedir, date, step, config.params)

        # Else post-processing the data
        bar()

        print("Sleeping {:d} seconds ...".format(sleeping_time))
        time.sleep(sleeping_time)
























