# -*- coding: utf-8 -*-
# vim: ft=sls

{%- set tplroot = tpldir.split('/')[0] %}
{%- from tplroot ~ "/map.jinja" import prometheus as p with context %}
{%- from tplroot ~ "/files/macros.jinja" import format_kwargs with context %}
{%- from tplroot ~ "/libtofs.jinja" import files_switch with context %}
{%- set sls_config_users = tplroot ~ '.config.users' %}

include:
  - {{ sls_config_users }}

prometheus-archive-install-prerequisites:
        {%- if grains.os != 'Windows' %}
  pkg.installed:
    - names: {{ p.pkg.deps|json }}
        {%- endif %}
  file.directory:
    - name: {{ p.dir.var }}
    - makedirs: True
    - require:
      - sls: {{ sls_config_users }}
        {%- if grains.os != 'Windows' %}
    - mode: 755
    - user: {{ p.identity.rootuser }}
    - group: {{ p.identity.rootgroup }}
        {%- endif %}

    {%- for name in p.wanted.component %}

prometheus-archive-directory-{{ name }}:
  file.directory:
    - name: {{ p.pkg.component[name]['path'] }}
    - makedirs: True
        {%- if grains.os != 'Windows' %}
    - user: {{ p.identity.rootuser }}
    - group: {{ p.identity.rootgroup }}
    - mode: '0755'
    - recurse:
        - user
        - group
        - mode
        {%- endif %}
prometheus-archive-install-{{ name }}:
        {%- if p.pkg.component.get(name).get('archive').get('tar', true) %}
  archive.extracted:
    {{- format_kwargs(p.pkg.component[name]['archive']) }}
    - trim_output: true
    - enforce_toplevel: false
    - options: --strip-components=1
    - force: {{ p.force }}
    - retry: {{ p.retry_option|json }}
    - require:
      - file: prometheus-archive-directory-{{ name }}
          {%- if grains.os != 'Windows' %}
    - user: {{ p.identity.rootuser }}
    - group: {{ p.identity.rootgroup }}
          {%- endif %}
        {% else %}
  file.managed:
    - name: {{ p.pkg.component[name]['path'] }}/{{ name }}
    - source: {{ p.pkg.component[name]['archive']['source'] }}
    - source_hash: {{ p.pkg.component[name]['archive']['source_hash'] }}
    - mode: '0755'
    - require:
      - file: prometheus-archive-directory-{{ name }}
          {%- if grains.os != 'Windows' %}
    - user: {{ p.identity.rootuser }}
    - group: {{ p.identity.rootgroup }}
          {%- endif %}
        {%- endif %}
        {%- if (grains.kernel|lower == 'linux' and p.linux.altpriority|int <= 0) or grains.os_family|lower in ('macos', 'arch') %}
            {%- if 'commands' in p.pkg.component[name]  and p.pkg.component[name]['commands'] is iterable %}
                {%- for cmd in p.pkg.component[name]['commands'] %}

prometheus-archive-install-{{ name }}-file-symlink-{{ cmd }}:
  file.symlink:
                    {%- if 'service' in p.pkg.component[name] %}
    - name: {{ p.dir.symlink }}/sbin/{{ cmd }}
                    {%- else %}
    - name: {{ p.dir.symlink }}/bin/{{ cmd }}
                    {% endif %}
    - target: {{ p.pkg.component[name]['path'] }}/{{ cmd }}
    - force: True
    - require:
              {%- if p.pkg.component.get(name).get('archive').get('tar', true) %}
      - archive: prometheus-archive-install-{{ name }}
              {% else %}
      - file: prometheus-archive-install-{{ name }}
              {% endif %}

                {%- endfor %}
            {%- endif %}
        {%- endif %}
        {%- if 'service' in p.pkg.component[name] and p.pkg.component[name]['service'] is mapping %}

prometheus-archive-install-{{ name }}-file-directory:
  file.directory:
    - name: {{ p.dir.var }}{{ p.div }}{{ name }}
    - makedirs: True
            {%- if grains.os != 'Windows' %}
    - user: {{ name }}
    - group: {{ name }}
    - mode: '0755'
    - require:
      - user: prometheus-config-users-install-{{ name }}-user-present
      - group: prometheus-config-users-install-{{ name }}-group-present

            {%- endif %}
            {%- if grains.kernel|lower == 'linux' %}

prometheus-archive-install-{{ name }}-managed-service:
  file.managed:
    - name: {{ p.dir.service }}/{{ p.pkg.component[name]['service'].get('name', name) }}.service
    - source: {{ files_switch(['systemd.ini.jinja'],
                              lookup='prometheus-archive-install-' ~  name ~ '-managed-service'
                 )
              }}
    - mode: '0644'
    - user: {{ p.identity.rootuser }}
    - group: {{ p.identity.rootgroup }}
    - makedirs: True
    - template: jinja
    - context:
        desc: prometheus - {{ name }} service
        name: {{ name }}
        user: {{ name }}
        group: {{ name }}
        workdir: {{ p.dir.var }}/{{ name }}
        stop: ''
               {%- if name in ('node_exporter', 'consul_exporter') or 'config_file' not in p.pkg.component[name] %}
                 {%- set cmd = ' ' ~ p.pkg.component.get(name).get('service').get('command', '') %}
                 {%- set args = [] %}
                 {%- for param, value in p.pkg.component.get(name).get('service').get('args', {}).items() %}
                   {% do args.append("--" ~ param ~ "=" ~ value ) %}
                 {%- endfor %}
        start: {{ p.pkg.component[name]['path'] }}/{{ name }}{{ cmd }} {{ args|join(' ') }}
               {%- else %}
        start: {{ p.pkg.component[name]['path'] }}/{{ name }} --config.file {{ p.pkg.component[name]['config_file'] }}  # noqa 204
               {%- endif %}
    - require:
      - file: prometheus-archive-install-{{ name }}-file-directory
              {%- if p.pkg.component.get(name).get('archive').get('tar', true) %}
      - archive: prometheus-archive-install-{{ name }}
              {% else %}
      - file: prometheus-archive-install-{{ name }}
              {% endif %}
      - user: prometheus-config-users-install-{{ name }}-user-present
      - group: prometheus-config-users-install-{{ name }}-group-present
  cmd.run:
    - name: systemctl daemon-reload
    - require:
              {%- if p.pkg.component.get(name).get('archive').get('tar', true) %}
      - archive: prometheus-archive-install-{{ name }}
              {% else %}
      - file: prometheus-archive-install-{{ name }}
              {% endif %}

            {%- endif %}{# linux #}
        {%- endif %}{# service #}
    {%- endfor %}
