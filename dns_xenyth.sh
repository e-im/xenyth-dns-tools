#!/usr/bin/env sh

## Xenyth Cloud hook for acme.sh DNS-01 challenge.

##
## Requires jq
##
## Environment Variables Required:
##
## XENYTH_API_KEY="aba0e360-1e04-41b3-91a0-1f2263e1e0fb"
##
## NOTE: Xenyth Cloud does not have an API meant for public use, and as such
## does not have API keys. If you would like to use this, create a ticket and
## ask for a permanent token to be created. The default user tokens expire
## after 24 hours and are bound to a single IP address.

## Author: Evan McCarthy <evanmccarthy@outlook.com>
## GitHub: https://github.com/e-im/xenyth-dns-tools

dns_xenyth_add() {
	fulldomain="$(echo "$1" | _lower_case)"
	txtvalue="$2"

	XENYTH_API_KEY="${XENYTH_API_KEY:-$(_readaccountconf_mutable XENYTH_API_KEY)}"
	# Check if API Key is set
	if [ -z "$XENYTH_API_KEY" ]; then
		XENYTH_API_KEY=""
		_err "You did not specify Xenyth Cloud API key."
		_err "Please export XENYTH_API_KEY and try again."
		return 1
	fi

	_info "Using Xenyth Cloud DNS-01 validation"
	_debug fulldomain "$fulldomain"
	_debug txtvalue "$txtvalue"

	_saveaccountconf_mutable XENYTH_API_KEY "$XENYTH_API_KEY"

	# find Xenyth ID for zone
	_find_zone_id || return 1

	_debug _domain_id "$_domain_id"

	export _H1="Accept: application/json"
	export _H2="Authorization: $XENYTH_API_KEY"
	export _H3="Content-Type: application/json"
	_url="https://dashboard.xenyth.net/api/services/dns/$_domain_id/action/addrecord"
	_body=$(
		jq -nc \
			--arg query "$fulldomain" \
			--arg type TXT \
			--argjson data "$(
				jq -nc \
					--arg content "$txtvalue" \
					'$ARGS.named'
			)" \
			--arg ttl 600 \
			'$ARGS.named'
	)

	_debug _url "$_url"
	_debug _body "$_body"

	_response="$(_post "$_body" "$_url" "" "POST")"

	if [ ! $(echo "$_response" | jq -rc \".success\") ]; then
		_err "error in response: $_response"
		return 1
	fi
	_debug2 response "$_response"

	return 0
}

dns_xenyth_rm() {
	fulldomain="$(echo "$1" | _lower_case)"
	txtvalue="$2"

	XENYTH_API_KEY="${XENYTH_API_KEY:-$(_readaccountconf_mutable XENYTH_API_KEY)}"
	# Check if API Key is set
	if [ -z "$XENYTH_API_KEY" ]; then
		XENYTH_API_KEY=""
		_err "You did not specify Xenyth Cloud API key."
		_err "Please export XENYTH_API_KEY and try again."
		return 1
	fi

	_debug fulldomain "$fulldomain"
	_debug txtvalue "$txtvalue"

	_saveaccountconf_mutable XENYTH_API_KEY "$XENYTH_API_KEY"

	# find Xenyth ID for zone
	_find_zone_id || return 1

	_debug _domain_id "$_domain_id"

	# Get all records to find record ID (match type, query (zone) and content)
	export _H1="Accept: application/json"
	export _H2="Authorization: $XENYTH_API_KEY"
	_records=$(_get "https://dashboard.xenyth.net/api/services/dns/$_domain_id/action/getrecords")

	_debug2 _records "$_records"

	# The . after $fulldomain in this line is (unfortunately) important. Xenyth
	# will return the full zone here (with a trailing .) which acme.sh will not
	# pass. However, a `.` is not included at the end of the zone in the response
	# for all domains held, hence why its added here
	_recid=$(echo "$_records" | jq -rc ".current_records[] | select(.type==\"TXT\" and .query==\"$fulldomain.\" and .content==\"$txtvalue\").recid")
	_debug _recid "$_recid"

	if [ -z "$_recid" ]; then
		_err "Failed to find record ID for $fulldomain of type TXT with content $txtvalue"
		return 1
	fi

	export _H3="Content-Type: application/json"

	_url="https://dashboard.xenyth.net/api/services/dns/$_domain_id/action/delrecord"
	_body=$(
		jq -n \
			--arg recid "$_recid" \
			'$ARGS.named'
	)

	_debug _url "$_url"
	_debug _body "$_body"

	_response="$(_post "$_body" "$_url" "" "POST")"

	if [ ! $(echo "$_response" | jq -rc \".success\") ]; then
		_err "error in response: $_response"
		return 1
	fi
	_debug2 response "$_response"

	return 0
}

# Find the zone ID from the Xenyth API - used for all DNS operations
_find_zone_id() {
	_debug fulldomain "$fulldomain"

	export _H1="Authorization: $XENYTH_API_KEY"
	export _H2="Accept: application/json"
	_debug XENYTH_API_KEY "$XENYTH_API_KEY"

	_records=$(_get "https://dashboard.xenyth.net/api/services/dns/list")
	_debug2 _records "$_records"
	_debug domains "$(echo "$_records" | jq -rc '[.dns[].zone] | join(", ")')"

	_count=1
	while :; do
		_attempt=$(echo "$fulldomain" | cut -d . -f "${_count}"-)
		_debug _attempt "$_attempt"

		if [ -z "$_attempt" ]; then
			_err "Zone $fulldomain not found in Xenyth account"
			return 1
		fi

		_zone="$(echo "$_records" | jq -rc ".dns[] | select(.zone==\"$_attempt\")")"
		if [ "$_zone" ]; then
			_debug _zone "$_zone"
			_domain_id=$(echo "$_zone" | jq -rc '.id')
			_debug _domain_id "$_domain_id"

			if [ -z "$_domain_id" ]; then
				_err "Found domain in list but failed to extract _domain_id! Likely a bug!"
				return 1
			fi

			return 0
		fi
		_count=$(_math "$_count" + 1)
	done

	_err "Domain not found. Something is wrong!"
	return 1
}
