# -------------------------------------------------------------------
# - NAME:        GFS_combine.py
# - AUTHOR:      Reto Stauffer
# - DATE:        2018-11-02
# -------------------------------------------------------------------
# - DESCRIPTION: Takes the subsetted grib files and creates
#                combined NetCDF files (one netCDF file per
#                model initialization/folder).
# -------------------------------------------------------------------
# - EDITORIAL:   2018-11-02, RS: Created file on pc24-c707.
# -------------------------------------------------------------------
# - L@ST MODIFIED: 2018-11-09 16:12 on marvin
# -------------------------------------------------------------------



def get_netcdf_file_name(ncdir, date, postfix = None):
   """get_netcdf_file_name(ncdir, date, postfix = None)

   Generate the netcdf output file name.

   Parameters
   ----------
   ncdir : str
      Path where the files should be stored
   date : datetime object
      date and time of model initialization
   postfix : None or str
      if a string is given this will be appended to the
      file names.
   """

   if not postfix is None:
      if not isinstance(postfix, str):
         raise ValueError("postfix has to be a string if not None")
   if not isinstance(ncdir, str):
      raise ValueError("ncdir has to be a string")

   # Generate and return the output file name
   from os.path import join
   postfix = "" if postfix is None else "_{:s}".format(postfix)

   return join(ncdir, "GFS_{:s}_combined{:s}.nc".format(
            date.strftime("%Y%m%d_%H%M"), postfix)) 
   

   

   

if __name__ == "__main__":

   import os
   import sys
   import subprocess as sub
   import glob

   os.environ["TZ"] = "UTC"

   # Requires wgrib2, check if executable exists before
   # doing anything else
   import distutils.spawn
   check = distutils.spawn.find_executable("wgrib2")
   if not check:
      raise Exception("wgrib2 cannot be found on this computer. Stop.")

   # Directory with the grib files
   gribdir = "data"

   # Regexp expression to identify the files we will consider
   grbpattern = "GFS_[0-9]{8}_[0-9]{4}_f[0-9]{3}_.*_subset\.grb2$"

   # Directory where to store the netCDF files
   ncdir = "netcdf"

   if not os.path.isdir(ncdir):
      try:
         os.makedirs(ncdir)
      except Exception as e:
         raise Exception(e)

   # Searching for all directories
   import tempfile
   import datetime as dt
   from glob import glob
   import re
   dirs = glob(os.path.join(gribdir, "*")); dirs.sort()
   for directory in dirs: #glob(os.path.join(gribdir, "*")):
      if not re.match("^" + gribdir + "/[0-9]{12}$", directory): continue

      # Extracting date
      date = re.findall("^" + gribdir + "/([0-9]{12})$", directory)
      date = dt.datetime.strptime(date[0], "%Y%m%d%H%M")

      print("* Processing GFS run {:s}".format(date.strftime("%Y-%m-%d %H UTC"))),
      ncfile = get_netcdf_file_name(ncdir, date)

      if os.path.isfile(ncfile):
          print("... exists, skip")
          continue
      else: print("")

      # What we have to do:
      # (1) Find all grb2 files matching our pattern
      # (2) Combine all single grb2 files into one big grb2 file
      # (3) Convert the combined grb2 file to netcdf

      # (1) Find all files ...
      grbfiles = []
      pat = "^" + directory + "/" + grbpattern
      for file in glob(os.path.join(directory, "*")):
         if re.match(pat, file): grbfiles.append(file)
      print("   Found {:d} files matching".format(len(grbfiles)))
      grbfiles.sort()

      # (2) Combine files
      tmp = tempfile.NamedTemporaryFile(prefix = "GFS_combine_")
      try:
         for grb in grbfiles:
             with open(grb) as gid:
                 tmp.write("".join(gid.readlines()))
         tmp.flush()
      except Exception as e:
         raise Exception("problems merging the individual grib files! " + e)
         
      # (3) Convert to netcdf
      cmd = ["wgrib2", tmp.name, "-netcdf", ncfile]
      p   = sub.Popen(cmd, stdout = sub.PIPE, stderr = sub.PIPE)
      out, err = p.communicate()
      if not p.returncode == 0:
         print(err)
         raise Exception("problems converting grib to netcdf")

      tmp.close() # Destroy temporary file

