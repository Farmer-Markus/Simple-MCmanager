#!/usr/bin/env bash

echo "Entrypoint starting in $PWD"

if [[ -z $MC_VERSION ]]; then
	echo 'MC_VERSION not set!'
	exit 1
fi

if  [[ -z $MC_SOFTWARE ]]; then
	echo 'MC_SOFTWARE not set, using "vanilla"'
	MC_SOFTWARE='vanilla'
fi

if [[ -z $INIT_MEM ]]; then
	INIT_MEM='128M'
fi

if [[ -z $MAX_MEM ]]; then
	MAX_MEM='4G'
fi


eulaPath="$PWD/eula.txt"
jarPath="$PWD/server-${MC_SOFTWARE}.jar"

if [[ ! -f "$eulaPath" ]]; then
	echo 'Accepting eula'
	echo 'eula=true' > "$eulaPath"
fi

if [[ ! -f "$jarPath" ]]; then
	/opt/server-manager.sh -v "$MC_VERSION" -s "$MC_SOFTWARE" -o "$jarPath"

	if [[ $? -ne 0 ]]; then
		exit $?
	fi
fi


if [[ -z "$@" ]]; then
	exec java -Xms${INIT_MEM} -Xmx${MAX_MEM} ${JVM_FLAGS} -jar ${jarPath} ${MC_FLAGS}
else
	# Exec custom compose command
	exec "$@"
fi

echo 'Entrypoint finished'
