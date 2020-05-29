#!/bin/sh
# Migrates a SVN repository to a git repository.
#
# Author: Augusto Pascutti <augusto@phpsp.org.br>

COMMAND=$0;
SVN=`which svn 2> /dev/null`;
GIT=`which git 2> /dev/null`;
READER="";
RETURN="";
PWD=`pwd`;

#
#
#
function help() {
    echo "usage: $COMMAND <operation>";
    echo "";
    echo "  Operations";
    echo "      authors <path SVN repo> [authors.txt]";
    echo "      migrate <path SVN repo> <path GIT repo> [authors.txt]";
};

# Generate a file to be used as base of authors for Git
#
# $1            SVN repository
# $2[optional]  Destination file
function generate_authors() {
    _is_svn_dir $1;
    local SVN_DIR=$1;
    local AUTHORS_FILE=$2;
    local OPTION_INTERACTIVE="$3"
    # checks
    if [ -z $2 ]; then
      AUTHORS_FILE="./authors.txt";
    fi;
    if [ -f $AUTHORS_FILE ]; then
      _read_answer "The authors file already exists, want me to remove it?" "y,n";
      if [ "$READER" = "y" ]; then
        `rm $AUTHORS_FILE`;
        if [ $? -eq 0 ]; then
          echo "Removed!";
        else
          _raise_error "I could not remove it. Please, remove or specify another authors file!";
        fi;
      else
        _raise_error "Please, remove or specify another authors file!";
      fi
    fi;
    
    # generating
    echo " Repository : $SVN_DIR";
    echo " Destination: $AUTHORS_FILE";
    echo " Retrieving authors by svn log ...";
    o=`svn log $SVN_DIR | grep -e '^r[0-9]' | cut -d '|' -f 2 | sort | uniq`
    if [ -z "$OPTION_INTERACTIVE" ]; then
      _read_answer "Do you want me to help you create the file or you will do it by yourself?" "y,n";
      OPTION_INTERACTIVE="$READER";
    fi;
    for user in $o; do
      if [ $OPTION_INTERACTIVE = 'y' ]; then
        _read_answer "What is the real name of $user?";
        local user_name="$READER";
        _read_answer "What is the email of $user?";
        local user_email="$READER";
      else
        local user_name="$user";
        local user_email="$user@email.com";
      fi
      `echo "$user = $user_name <$user_email>" >> $AUTHORS_FILE`;
      if [ $? -ne 0 ]; then
        _raise_error "A problem ocurred generating authors file.";
      fi;
    done;
    
    echo " File successfully generated!";
    if [ $OPTION_INTERACTIVE = 'n' ]; then
      echo " Now, you must complete the file as follows:"
      echo "   kurt = Kurt Kobain <kurt@nirvana.com>";
      echo "   bart = Bart Simpson <bart@fox.com>";
      echo "   norris = Chuck Norris <chuck@norris.com>";
    fi;
    exit 0;
};

# Generates a GIT repo from a populated SVN repo
# 
# $1            SVN url/path
# $2            GIT repository destination
# $3[optional]  Author file to be used
function migrate_svn_repo() {
  local repo_svn=$1;
  local repo_git=$2;
  local authors=$3;
  local tmp_git="/tmp/git2svn-temp-repo"
  
  # Normalizing paths to absolute paths always
  _real_path "$repo_git";
  repo_git="$RETURN";
  
  # checks
  _is_svn_dir $repo_svn;
  if [ -z $repo_git ]; then
    _raise_error "GIT repository destination not specified!";
  fi;
  if [ -d $repo_git ]; then
    _read_answer "The GIT repository destination already exists, do you want to remove it?" "y,n";
     if [ "$READER" = "y" ]; then
       `rm -rf $repo_git`;
       if [ $? -ne 0 ]; then
         _raise_error "Failed to remove dir $repo_git";
       fi;
     else
       _raise_error "Please, remove or specify a different path to be the GIT repository";
     fi;
  fi;
  if [ -d $tmp_git ]; then
    `rm -rf $tmp_git`;
    if [ $? -ne 0 ]; then
      _raise_error "Unable to remove temporary git repository: $tmp_git";
    fi;
  fi
  
  # running
  echo "Creating temporary git repository in $tmp_git";
  _read_answer "Do you want to import svn:ignore properties?" "y,n";
  local OPTION_IGNORE=$READER;
  if [ -z "$authors" ]; then
    _read_answer "Do you want to use a file as referece for authors? (I will generate one)" "y,n";
    if [ "$READER" = "y" ]; then
      # generate authors file on the fly
      authors="/tmp/svn2git_authors.txt";
      generate_authors "$repo_svn" "$authors" "y";
      if [ $? -ne 0 ]; then
        _raise_error "Authors file not created correctly!";
      fi;
    fi;
  fi;
  # set authors option
  if [ -z "$authors" ]; then
    option_authors="";
  else
    option_authors="-A $authors";
  fi;
  echo "Creating temp git repository in $tmp_git ...";
  _git "svn clone $repo_svn --no-metadata --stdlayout $option_authors $tmp_git"
  echo "SVN repository cloned to a dirty (temporary) GIT repository";
  
  # see if we need to migrate svn:ignore
  if [ "$OPTION_IGNORE" = "y" ]; then
    echo "Migrating svn:ignore property";
    cd "$tmp_git";
    _git "svn show-ignore > '.gitignore'"
    _git "add .gitignore";
    _git "commit -m '[svn2git] Converting svn:ignore properties to .gitignore.'"
    cd $PWD;
  fi;
  
  # init the clean new GIT repository
  echo "Creating new git repository in $repo_git";
  _git "init --bare $repo_git";
  echo " Pushing changes from the TEMP git repository to the FINAL repository ...";
  cd "$tmp_git";
  _git "remote add bare $repo_git"
  _git "push bare master";
};

# Aux functions ------------------------------------------------------------------------

# Returns the real path of a given path/file.
# The result goes into the $RETURN global variable.
#
# $1    Path
function _real_path() {
  local _path="$1";
  local _real="";
  local _actual=`pwd`;
  local _sufix="";
  # if the given path is a file
  if [ -f $_path ] || [ ! -d $_path ]; then
    _sufix="/${_path##*/}";
    _path=${_path%/*};
  fi;
  # If the given path is a dir already
  if [ -d $_path ]; then
    cd "$_path";
    if [ $? -ne 0 ]; then
      _raise_error "Could not get real path of $_path";
    fi;
  fi;
  _real=`pwd`;
  RETURN="$_real$_sufix";
  cd "$_actual";
};

# Executes a git command
#
# $1    Command to be executed
function _git() {
  echo "git $1 > /dev/null";
  `git $1 > /dev/null 2> /dev/null`;
  if [ $? -ne 0 ]; then
    _raise_error "Git command failed!";
  fi;
};

# Shows a question and reads the answer putting it on $READER.
# This function also works with options, an answer must be
# some of the given options.
#
# $1      Question
# $2      Options (comma separated)
function _read_answer() {
  if [ -z "$2" ]; then
    _ask_question "$1";
    return 0;
  fi;
  _ask_question "$1 [$2]";  
  for option in ` echo "$2" | sed s/,/\ /g`; do
    if [ "$READER" = "$option" ]; then
      return 0;
    fi;
  done;
  READER="";
  RETURN="$READER";
  _read_answer "$1" "$2";
  return 1;
};

# Shows a question and reads the answer putting it on $READER
#
# $1      Question
function _ask_question() {
  echo " $1 ";
  read READER;
  RETURN="$READER";
};

# finishes the script with an error
#
# $1    Error message
function _raise_error() {
    echo "Error: $1";
    exit 2;
};

# Checks if the given directory/url is a valid SVN directory
#
# $1    SVN directory
function _is_svn_dir() {
    local d=$1;
    if [ -z "$d" ]; then 
      _raise_error "SVN dir/url not especified!"; 
    fi;
    `$SVN info $d > /dev/null 2> /dev/null`;
    if [ $? -eq 0 ]; then
      return 0;
    fi;
    _raise_error "SVN dir/url is not a valid!";
};

# Parse command line arguments ---------------------------------------------------------
if [ -z "$SVN" ]; then
  _raise_error "svn binary not found";
fi;
if [ -z "$GIT" ]; then
  _raise_error "git binary not found";
fi;

case $1 in
    "authors") generate_authors $2 ;;
    "migrate") migrate_svn_repo $2 $3 $4;;
    *) help; exit 0;;
esac;