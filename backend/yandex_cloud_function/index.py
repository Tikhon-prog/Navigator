import hashlib
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

def sha256(value):
    return hashlib.sha256(value.encode('utf-8')).hexdigest()

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
        if path == '/admin/login' and event.get('httpMethod') == 'POST':
            body = json.loads(event.get('body') or '{}')
            login = str(body.get('login', ''))
            password = str(body.get('password', ''))
            data = read_grid('Admins')
            for row in data.get('rows', []):
                values = row.get('row', [])
                if len(values) >= 5 and values[1] == login and values[2] == sha256(password) and values[4] is not False:
                    return response(200, {'ok': True, 'role': values[3], 'admin_id': row.get('id')})
            return response(401, {'ok': False})
        return response(404, {'ok': False, 'error': 'not_found'})
    except Exception as exc:
        return response(500, {'ok': False, 'error': str(exc)})
