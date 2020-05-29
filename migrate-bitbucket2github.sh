#!/bin/bash

BB_USERNAME=your_bitbucket_username 
BB_PASSWORD=your_bitbucket_password

GH_USERNAME=your_github_username
GH_ACCESS_TOKEN=your_github_access_token

###########################

pagelen=$(curl -s -u $BB_USERNAME:$BB_PASSWORD https://api.bitbucket.org/2.0/repositories/$BB_USERNAME | jq -r '.pagelen')

echo "Total number of pages: $pagelen"

hr () {
  printf '%*s\n' "${COLUMNS:-$(tput cols)}" '' | tr ' ' -  
}

i=1

while [ $i -le $pagelen ]
do
  echo
  echo "* Processing Page: $i..."
  hr  
  pageval=$(curl -s -u $BB_USERNAME:$BB_PASSWORD https://api.bitbucket.org/2.0/repositories/$BB_USERNAME?page=$i)

  next=$(echo $pageval | jq -r '.next')
  slugs=($(echo $pageval | jq -r '.values[] | .slug'))
  repos=($(echo $pageval | jq -r '.values[] | .links.clone[1].href'))

  j=0
  for repo in ${repos[@]}
  do
    echo "$(($j + 1)) = ${repos[$j]}"
    slug=${slugs[$j]}
  git clone --bare $repo 
  cd "$slug.git"
  echo
  echo "* $repo cloned, now creating $slug on github..."  
  echo  

  read -r -d '' PAYLOAD <<EOP
  {
    "name": "$slug",
    "description": "$slug - moved from bitbucket",
    "homepage": "https://github.com/$slug",
    "private": true
  }
  EOP

  curl -H "Authorization: token $GH_ACCESS_TOKEN" --data "$PAYLOAD" \
      https://api.github.com/user/repos
  echo
  echo "* mirroring $repo to github..."  
  echo
  git push --mirror "git@github.com:$GH_USERNAME/$slug.git"
  j=$(( $j + 1 ))
  hr    
  cd ..
  done  
  i=$(( $i + 1 ))
done