#! /bin/bash

_HOME2_=$(dirname $0)
export _HOME2_
_HOME_=$(cd $_HOME2_;pwd)
export _HOME_

basedir="$_HOME_""/../"
f1="Antidote.xcodeproj/project.pbxproj"
f2="pushextension/Info.plist"

cd "$basedir"

if [[ $(git status --porcelain --untracked-files=no) ]]; then
	echo "ERROR: git repo has changes."
	echo "please commit or cleanup the git repo."
	exit 1
else
	echo "git repo clean."
fi

cur_p_version=$(cat "$f1" | grep 'CURRENT_PROJECT_VERSION' | head -1 | \
	sed -e 's#^.*CURRENT_PROJECT_VERSION = ##' | \
	sed -e 's#;.*$##')
cur_m_version=$(cat "$f1" | grep 'MARKETING_VERSION' | head -1 | \
	sed -e 's#^.*MARKETING_VERSION = ##' | \
	sed -e 's#;.*$##')


# cur_p_version=149900
# cur_m_version=1.4.99
# cur_p_version=150000
# cur_m_version=1.5.00

next_p_version=$[ $cur_p_version + 100 ]
# thanks to: https://stackoverflow.com/a/8653732
next_m_version=$(echo "$cur_m_version"|awk -F. -v OFS=. 'NF==1{print ++$NF}; NF>1{if(length($NF+1)>length($NF))$(NF-1)++; $NF=sprintf("%0*d", length($NF), ($NF+1)%(10^length($NF))); print}')

echo $cur_p_version
echo $next_p_version

echo $cur_m_version
echo $next_m_version

sed -i -e 's#CURRENT_PROJECT_VERSION = .*;#CURRENT_PROJECT_VERSION = '"$next_p_version"';#g' "$f1"
sed -i -e 's#MARKETING_VERSION = .*;#MARKETING_VERSION = '"$next_m_version"';#g' "$f1"

sed -i -e 's#'"$cur_m_version"'#'"$next_m_version"'#g' "$f2"
sed -i -e 's#'"$cur_p_version"'#'"$next_p_version"'#g' "$f2"

commit_message="v""$next_m_version"
tag_name="$next_m_version"

git commit -m "$commit_message" "$f1" "$f2"
git tag -a "v$next_m_version" -m "v$next_m_version"
