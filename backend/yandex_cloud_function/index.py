import json
import os
import requests

WIKI = 'https://api.wiki.yandex.net/v1'
TOKEN = os.environ.get('WIKI_TOKEN', '')
ORG_ID = os.environ.get('ORG_ID', '')
GRID_IDS = json.loads(os.environ.get('GRID_IDS_JSON', '{}'))


def headers():
    return {'Authorization': f'OAuth {TOKEN}', 'X-Org-Id': ORG_ID, 'Content-Type': 'application/json'}


def grid(name):
    return GRID_IDS.get(name)


def read_grid(name):
    gid = grid(name)
    if not gid:
        raise RuntimeError(f'Grid {name} is not configured')
    r = requests.get(f'{WIKI}/grids/{gid}', headers=headers(), timeout=15)
    r.raise_for_status()
    return r.json()



def response(status, body):
    return {'statusCode': status, 'headers': {'Content-Type': 'application/json; charset=utf-8', 'Access-Control-Allow-Origin': '*'}, 'body': json.dumps(body, ensure_ascii=False)}


def handler(event, context):
    if event.get('httpMethod') == 'OPTIONS':
        return response(200, {'ok': True})
    path = event.get('path', '/')
    try:
        if path == '/health':
            return response(200, {'ok': True, 'service': 'navigator'})
        if path == '/schedule':
            class_id = (event.get('queryStringParameters') or {}).get('class_id', '')
            data = read_grid('BaseSchedule')
            return response(200, {'class_id': class_id, 'revision': data.get('revision'), 'rows': data.get('rows', [])})
        if path == '/supplements':
            data = read_grid('Supplements')
            return response(200, {'revision': data.get('revision'), 'rows': data.get('rows', [])})
        if path == '/announcements':
            data = read_grid('Announcements')
            return response(200, {'revision': data.get('revision'), 'rows': data.get('rows', [])})
        if path == '/admin/login':
            # Do not claim to authenticate admins until password KDF, rate limiting,
            # session issuance, and authorization checks are implemented server-side.
            return response(503, {'ok': False, 'error': 'admin_auth_not_configured'})
        return response(404, {'ok': False, 'error': 'not_found'})
    except Exception:
        # Keep credentials, provider URLs, and internal exception details out of responses.
        return response(500, {'ok': False, 'error': 'internal_error'})
