"""Create the Navigator grid set in Yandex Wiki."""
import os, requests
API='https://api.wiki.yandex.net/v1'
TOKEN=os.environ['WIKI_TOKEN']; ORG=os.environ['ORG_ID']; PAGE=os.environ.get('WIKI_PAGE_SLUG','navigator-data')
H={'Authorization':f'OAuth {TOKEN}','X-Org-Id':ORG,'Content-Type':'application/json'}
TABLES=['Admins','Classes','BaseSchedule','Supplements','Rooms','Places','Announcements','Devices','AuditLog','Settings']
page=requests.get(f'{API}/pages/{PAGE}',headers=H,timeout=20)
page.raise_for_status(); page_id=page.json().get('id')
for title in TABLES:
    r=requests.post(f'{API}/grids',headers=H,json={'page':{'id':page_id},'title':title},timeout=20)
    r.raise_for_status(); print(title, r.json().get('id'))
