# ArgoCD

## Argocd deployment with kustomize

```bash
# Create namespace
kubectl create ns argocd

# Deploy argocd
kubectl apply --server-side -k bootstrap/argocd/overlays/k8s.atealab.se

# Check that all pods are running
kubectl -n argocd get pods

# Get initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo

# Navigate to https://argocd.k8s.atealab.se and login with username "admin" and the password retrieved above.
```

## Connect argocd to LDAP

### Step 1: Create the Service Account Secret

```bash
kubectl create secret generic argocd-dex-ad-credentials \
  --namespace argocd \
  --from-literal=bindPW='YourServiceAccountPassword'
```

### Step 2: Configure Dex LDAP Connector

Add the followings to the argocd-cm ConfigMap to add the Dex LDAP connector pointing to your AD:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
data:
  url: https://argocd.k8s.atealab.se

  dex.config: |
    connectors:
    - type: ldap
      name: Active Directory
      id: active-directory
      config:
        # AD domain controller - always use LDAPS (port 636)
        host: ad01.ad.atealab.se:636

        # TLS settings
        insecureNoSSL: false
        insecureSkipVerify: true
        # If using internal CA, reference the CA cert
        # rootCAData: <base64-encoded-ca-certificate>

        # Service account for LDAP bind
        bindDN: CN=ldapbind,OU=Service Accounts,DC=ad,DC=atealab,DC=se
        bindPW: $dex.ldap.bindPW

        # User search configuration
        userSearch:
          # Where to search for users
          baseDN: CN=Users,DC=ad,DC=atealab,DC=se
          # Filter to find user accounts only (not computers, etc.)
          filter: "(&(objectClass=person)(!(userAccountControl:1.2.840.113556.1.4.803:=2)))"
          # AD attribute used as the login username
          username: sAMAccountName
          # Unique identifier
          idAttr: sAMAccountName
          # Email attribute
          emailAttr: userPrincipalName
          # Display name
          nameAttr: displayName

        # Group search configuration
        groupSearch:
          # Where to search for groups
          # baseDN: OU=Groups,DC=corp,DC=example,DC=com
          baseDN: DC=ad,DC=atealab,DC=se
          # Filter for security groups
          filter: "(objectClass=group)"
          # How to match users to groups
          userMatchers:
          - userAttr: DN
            groupAttr: member
          # Group name attribute
          nameAttr: cn
```

### Step 3: Configure the Dex Secret Reference

```bash
kubectl patch secret argocd-secret -n argocd \
  --type merge \
  -p '{"stringData": {"dex.ldap.bindPW": "YourServiceAccountPassword"}}'
```

### Step 4: Map AD Groups to ArgoCD RBAC Roles

Now configure the RBAC policy to map AD security groups to ArgoCD roles:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-rbac-cm
  namespace: argocd
data:
  # Default: no access unless mapped
  policy.default: role:readonly

  # Use AD group names for RBAC
  scopes: '[groups, email]'

  policy.csv: |
    # Platform team gets admin access
    p, role:platform-admin, applications, *, */*, allow
    p, role:platform-admin, clusters, *, *, allow
    p, role:platform-admin, repositories, *, *, allow
    p, role:platform-admin, projects, *, *, allow
    p, role:platform-admin, accounts, *, *, allow
    p, role:platform-admin, gpgkeys, *, *, allow

    # Developers can view and sync their project apps
    p, role:developer, applications, get, */*, allow
    p, role:developer, applications, list, */*, allow
    p, role:developer, applications, sync, */*, allow
    p, role:developer, logs, get, */*, allow

    # QA team can view applications
    p, role:qa, applications, get, */*, allow
    p, role:qa, applications, list, */*, allow

    # Map AD groups to ArgoCD roles
    g, TalosAdmins, role:platform-admin
    # g, Platform-Engineering, role:platform-admin
    # g, DevOps-Team, role:platform-admin
    # g, Application-Developers, role:developer
    # g, QA-Engineers, role:qa
```

>> INFO: The g lines are the group mappings. The group names must match exactly what AD returns as the cn attribute of the group.

### Step 5: Restart Dex and Verify

After making ConfigMap changes, restart the Dex server:

```bash
kubectl rollout restart deployment argocd-dex-server -n argocd
```

- Now try logging in to ArgoCD with an AD user

```bash
# Test via CLI
argocd login argocd.k8s.atealab.se --sso
```

## Troubleshooting

```bash
# Test LDAP bind directly
ldapsearch -H ldaps://ad01.ad.atealab.se:636 \
  -D "CN=ldapbind,OU=Service Accounts,DC=ad,DC=atealab,DC=se" \
  -W -b "CN=Users,DC=ad,DC=atealab,DC=se" "(sAMAccountName=testuser)"
