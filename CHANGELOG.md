# [1.10.0](https://github.com/MicroTodoSuite/microservice-app-ops/compare/v1.9.0...v1.10.0) (2026-09-13)


### Features

* **shd:** add the shared dns root ([#69](https://github.com/MicroTodoSuite/microservice-app-ops/issues/69)) ([fb841b9](https://github.com/MicroTodoSuite/microservice-app-ops/commit/fb841b98212bc7572ef3723ca572131f9d836ddc)), closes [#68](https://github.com/MicroTodoSuite/microservice-app-ops/issues/68) [#67](https://github.com/MicroTodoSuite/microservice-app-ops/issues/67)
* **shd:** add the shared registry root ([#68](https://github.com/MicroTodoSuite/microservice-app-ops/issues/68)) ([d7993e0](https://github.com/MicroTodoSuite/microservice-app-ops/commit/d7993e0fbd8d3678b15c1319ab18fa647c7d7c0c)), closes [#67](https://github.com/MicroTodoSuite/microservice-app-ops/issues/67)
* **shd:** implement the shared DNS root ([ebc9401](https://github.com/MicroTodoSuite/microservice-app-ops/commit/ebc940171e99fd84c0401680c6ec4070c071ccb1))
* **shd:** implement the shared registry root ([9d757cd](https://github.com/MicroTodoSuite/microservice-app-ops/commit/9d757cd663ad767894b8a08c5425ec0c7a8859a5))

# [1.9.0](https://github.com/MicroTodoSuite/microservice-app-ops/compare/v1.8.0...v1.9.0) (2026-09-13)


### Features

* **shd:** add the shared security root ([#67](https://github.com/MicroTodoSuite/microservice-app-ops/issues/67)) ([656f0b3](https://github.com/MicroTodoSuite/microservice-app-ops/commit/656f0b35f6be378de3259cba54e56d125385d126))
* **shd:** implement the shared security root ([bf3bdee](https://github.com/MicroTodoSuite/microservice-app-ops/commit/bf3bdee608f3e62ce31e0f4cc8a713b14dc6b780))

# [1.8.0](https://github.com/MicroTodoSuite/microservice-app-ops/compare/v1.7.0...v1.8.0) (2026-09-13)


### Features

* **shd:** add the shared state root ([507f0d7](https://github.com/MicroTodoSuite/microservice-app-ops/commit/507f0d7ba8cab78a6c7e75ad3193b77064c57cd8))
* **shd:** add the shared state root ([#66](https://github.com/MicroTodoSuite/microservice-app-ops/issues/66)) ([13a1636](https://github.com/MicroTodoSuite/microservice-app-ops/commit/13a163615aec9d2329614df1e18ced41165c1461)), closes [.github#17](https://github.com/.github/issues/17) [terraform-aws-modules#2](https://github.com/terraform-aws-modules/issues/2)

# [1.7.0](https://github.com/MicroTodoSuite/microservice-app-ops/compare/v1.6.0...v1.7.0) (2026-09-13)


### Features

* **irsa:** add a read-only ecr role for trivy operator ([1271f0b](https://github.com/MicroTodoSuite/microservice-app-ops/commit/1271f0bda2c7be049193de338c230334443d1a42)), closes [#133](https://github.com/MicroTodoSuite/microservice-app-ops/issues/133)
* **irsa:** add a read-only ecr role for trivy operator ([#63](https://github.com/MicroTodoSuite/microservice-app-ops/issues/63)) ([70ece00](https://github.com/MicroTodoSuite/microservice-app-ops/commit/70ece00356a319de3efb94c0736ea6d1ad2e709e)), closes [MicroTodoSuite/microservice-app-gitops#133](https://github.com/MicroTodoSuite/microservice-app-gitops/issues/133) [#133](https://github.com/MicroTodoSuite/microservice-app-ops/issues/133)

# [1.6.0](https://github.com/MicroTodoSuite/microservice-app-ops/compare/v1.5.2...v1.6.0) (2026-09-13)


### Features

* **lifecycle:** snapshot persistent volumes before quiescence ([2fc2486](https://github.com/MicroTodoSuite/microservice-app-ops/commit/2fc24862db6fda5c64a8cb1c689b46bbb3cb66d9))
* **lifecycle:** snapshot persistent volumes before quiescence ([#61](https://github.com/MicroTodoSuite/microservice-app-ops/issues/61)) ([6acc370](https://github.com/MicroTodoSuite/microservice-app-ops/commit/6acc37046c06adda1b6d80cbb1460ae5dc8bf748)), closes [gitops#109](https://github.com/gitops/issues/109)

## [1.5.2](https://github.com/MicroTodoSuite/microservice-app-ops/compare/v1.5.1...v1.5.2) (2026-09-11)


### Bug Fixes

* **lifecycle:** canonicalize saved bundle paths ([1e64e13](https://github.com/MicroTodoSuite/microservice-app-ops/commit/1e64e13b3c0f0afc9e2e8780a5430cc892a99534))
* **lifecycle:** keep bundle fixture self-contained ([29baf87](https://github.com/MicroTodoSuite/microservice-app-ops/commit/29baf8794c28eaa0eb15954a3027361699a77682))

## [1.5.1](https://github.com/MicroTodoSuite/microservice-app-ops/compare/v1.5.0...v1.5.1) (2026-09-11)


### Bug Fixes

* **lifecycle:** allow cluster OIDC shutdown ([5ac34e9](https://github.com/MicroTodoSuite/microservice-app-ops/commit/5ac34e9aa347725525e6ef7883649fdec366b927))

# [1.5.0](https://github.com/MicroTodoSuite/microservice-app-ops/compare/v1.4.0...v1.5.0) (2026-09-11)


### Bug Fixes

* **aws:** isolate demo foundation shared resources ([615af2c](https://github.com/MicroTodoSuite/microservice-app-ops/commit/615af2c79b2b350aa70f98f92ebf0517a3ff0d15))
* **aws:** pin bootstrap AMI release to the version actually running ([d2e10a9](https://github.com/MicroTodoSuite/microservice-app-ops/commit/d2e10a94717dbc21fb719a243b51cdb456b10074))
* **aws:** provision the demo environment's JWT secret and reader ([2121c9e](https://github.com/MicroTodoSuite/microservice-app-ops/commit/2121c9e4dec81716161ebd10d60775c9126813eb)), closes [microservice-app-gitops#56](https://github.com/microservice-app-gitops/issues/56)
* **aws:** reconfigure replacement backend ([b06d128](https://github.com/MicroTodoSuite/microservice-app-ops/commit/b06d128b20d9293ba1b5eb2d850af668a4ab8565))
* **eks:** enable vpc-cni prefix delegation to raise pod capacity per node ([b648527](https://github.com/MicroTodoSuite/microservice-app-ops/commit/b648527c1abcf419b40d5b9527e9a3352471e570))
* generate release secrets without remote calls ([bc9634f](https://github.com/MicroTodoSuite/microservice-app-ops/commit/bc9634fd1268a9d99d38036bb0e466c447e87569))
* **lifecycle:** use Make syntax throughout runbook ([e6d4914](https://github.com/MicroTodoSuite/microservice-app-ops/commit/e6d49140d20dd2955d0fa0cb5fb4b5f22c256304))
* **preflight:** drop the unpinned ripgrep dependency ([bef84ca](https://github.com/MicroTodoSuite/microservice-app-ops/commit/bef84caa22f540ac5f2766e737b1e8be52a04f91))
* **release:** use native GitHub token ([f1f723f](https://github.com/MicroTodoSuite/microservice-app-ops/commit/f1f723fbbf3145f27d9bfa29e8fdab440d75a2e5))
* **tests:** read committed configuration in the foundation contract ([0c4600b](https://github.com/MicroTodoSuite/microservice-app-ops/commit/0c4600b33d06cd8f1afa79f741a7b7680ebe3e0b))


### Features

* **aws:** add the canonical microtodosuite.online zone off by default ([d4355e5](https://github.com/MicroTodoSuite/microservice-app-ops/commit/d4355e50d95dc0378a6dd8d09bc988e0db873ae1))
* **aws:** add the dev-owned platform image mirror behind its own role ([3391703](https://github.com/MicroTodoSuite/microservice-app-ops/commit/339170375953f0a6cb63080b78b110702598bb84))
* **aws:** add the full-profile secret containers and their readers ([741703e](https://github.com/MicroTodoSuite/microservice-app-ops/commit/741703ef357e0e6bc3df638d1cc4330b7baef55f))
* **aws:** allow shared_environments to include environments beyond dev staging prod ([f92b531](https://github.com/MicroTodoSuite/microservice-app-ops/commit/f92b5311103378b337570e6b4a8bcfa105b7621c))
* **aws:** declare the AWS account once and move it with one command ([#33](https://github.com/MicroTodoSuite/microservice-app-ops/issues/33)) ([0b34d78](https://github.com/MicroTodoSuite/microservice-app-ops/commit/0b34d7814810a29fbcd280fc48d1cfef04be79d2))
* **aws:** expose the full-profile inputs on the foundation root ([8a9f311](https://github.com/MicroTodoSuite/microservice-app-ops/commit/8a9f3110c4d35a79ab62f88ff0f7b46d5188e7c1))
* **aws:** generalize foundation for demo-full ([19e649b](https://github.com/MicroTodoSuite/microservice-app-ops/commit/19e649b69d2658e367705daf73b91d117502c856))
* **aws:** generalize the foundation for full-profile clusters ([06a4ca0](https://github.com/MicroTodoSuite/microservice-app-ops/commit/06a4ca099debafc4299ba2954ee472beff7a9d4e))
* **aws:** let reviewed extra clusters assume the shared reader roles ([746ef3f](https://github.com/MicroTodoSuite/microservice-app-ops/commit/746ef3f0263cb176085d85b6bec8fa91c85c2525))
* **aws:** migrate economical foundation account ([c7630ef](https://github.com/MicroTodoSuite/microservice-app-ops/commit/c7630efa0fcff42e769c04d43137d48d7d047c33))
* **eks:** add EBS CSI driver managed addon with least-privilege IRSA ([6918f5d](https://github.com/MicroTodoSuite/microservice-app-ops/commit/6918f5de316de5ee5413bf633382445fc1ccaf30))
* enable VPC CNI network-policy enforcement via managed add-on configuration and update Terraform validation logic ([c5ecbda](https://github.com/MicroTodoSuite/microservice-app-ops/commit/c5ecbda8656a72759111b8f6d6a4e6b531cb8df2))
* establish MicroTodoSuite engineering constitution and specify initial environment options ([53bcf84](https://github.com/MicroTodoSuite/microservice-app-ops/commit/53bcf8482f79760befbe2075d8700dd895acdd55))
* **iam:** add irsa roles and secret containers for observability/security slack readers ([0b19d8c](https://github.com/MicroTodoSuite/microservice-app-ops/commit/0b19d8cc3ad7173b908e5218872a5c1cdd30ba80))
* **iam:** wire observability and security secrets-reader roles through dev foundation ([6d282d9](https://github.com/MicroTodoSuite/microservice-app-ops/commit/6d282d9ef838f8af579686ba87c5fc3029593efa))
* implement AWS dev foundation infrastructure and state backend modules with full specification documentation ([798728e](https://github.com/MicroTodoSuite/microservice-app-ops/commit/798728e095167f4e5167d44834c4eec00d414b8d))
* **lifecycle:** add Make operator interface ([2d275f7](https://github.com/MicroTodoSuite/microservice-app-ops/commit/2d275f7f5ace1fe72f714da54a5b655644553109))
* **lifecycle:** implement profile-aware runtime control ([d99b5af](https://github.com/MicroTodoSuite/microservice-app-ops/commit/d99b5afc9d0236ca06ae544ff58312d99c18b3e0))
* **lifecycle:** use portable state checks ([5cb8a17](https://github.com/MicroTodoSuite/microservice-app-ops/commit/5cb8a17788d6865effb11a73cab30304ef63a77a))
* **preflight:** add fail-closed Azure DR discovery ([2da0ab9](https://github.com/MicroTodoSuite/microservice-app-ops/commit/2da0ab99fcad540d04a582be8e5db2d177852119))
* provision namespace release prerequisites ([1a9da1e](https://github.com/MicroTodoSuite/microservice-app-ops/commit/1a9da1e4e778e7e5afc119d97172893c0e2d850d))
* update bootstrap node instance type to m7i-flex.large, enable name prefixes for node groups, and refine EKS KMS configuration. ([c38c853](https://github.com/MicroTodoSuite/microservice-app-ops/commit/c38c853de849350fe53dc4cb0033f9ffb4e81326))
* **us2:** isolated full-profile AWS foundations and shared egress hub ([#26](https://github.com/MicroTodoSuite/microservice-app-ops/issues/26)) ([8a6a163](https://github.com/MicroTodoSuite/microservice-app-ops/commit/8a6a163c8181152c147d61f8af136ec4ad8ba223))

# [1.4.0](https://github.com/MicroTodoSuite/microservice-app-ops/compare/v1.3.0...v1.4.0) (2025-04-25)


### Bug Fixes

* fix errors ([48a486b](https://github.com/MicroTodoSuite/microservice-app-ops/commit/48a486b4ad5e22be583f7732f1e833f0496554a4))
* fix order of variables in terrafom plan ([2801d28](https://github.com/MicroTodoSuite/microservice-app-ops/commit/2801d28a8ab66382570025d76cf53f402267287a))
* **pipeline:** add new values to pipeline ([c45afd3](https://github.com/MicroTodoSuite/microservice-app-ops/commit/c45afd3eb553d0fe37555b20e60919d5f5b61752))
* **pipeline:** chage name of tfplan to tfplan-containers ([66756c7](https://github.com/MicroTodoSuite/microservice-app-ops/commit/66756c7e3a22eec70b7b963af73d8a0156325bf5))
* **pipeline:** delete path ([2fd22f2](https://github.com/MicroTodoSuite/microservice-app-ops/commit/2fd22f20acfe00845309f8af22a172c3bc2f1ebd))
* **pipeline:** remove working-directory of terraform plans ([04e66d1](https://github.com/MicroTodoSuite/microservice-app-ops/commit/04e66d12f62c5904f7cc5c009ab52037802c1e0f))
* **pipeline:** rollback of deploy pipeline ([371b578](https://github.com/MicroTodoSuite/microservice-app-ops/commit/371b578075953769404964e31b2144b8029ed526))
* **pipeline:** update pipeline ([cd9cbf8](https://github.com/MicroTodoSuite/microservice-app-ops/commit/cd9cbf851a31412698e798a0f69587b8fd17fc8a))
* **pipeline:** update pipeline ([1cc2b25](https://github.com/MicroTodoSuite/microservice-app-ops/commit/1cc2b25f8ea1216058842871745c478f86fde4aa))
* **pipeline:** update pipeline ([404f6e1](https://github.com/MicroTodoSuite/microservice-app-ops/commit/404f6e1a5ed8ae7761797613be70f83b2809774b))
* **pipeline:** update pipeline of deploy ([2fe6f17](https://github.com/MicroTodoSuite/microservice-app-ops/commit/2fe6f17540b03aca72dc79f116f436fe3359fda4))
* **pipeline:** update pipeline of deploy ([c3aa43d](https://github.com/MicroTodoSuite/microservice-app-ops/commit/c3aa43d36584db00604db1e7663cad19c1b07da8))
* **pipeline:** update pipeline of deploy ([ee1c13e](https://github.com/MicroTodoSuite/microservice-app-ops/commit/ee1c13ef75d6e14c0decd722a8952006f00b2986))
* **pipeline:** update pipeline of deploy ([b8c86f4](https://github.com/MicroTodoSuite/microservice-app-ops/commit/b8c86f46e9d1a11067511fc2ce53851ef05a76fd))
* **script:** update script ([735fb1a](https://github.com/MicroTodoSuite/microservice-app-ops/commit/735fb1a0b2ff2826838786bbca802d73b155bf35))
* **script:** update setup azure secrets ([821be92](https://github.com/MicroTodoSuite/microservice-app-ops/commit/821be92f5d64e813e1ceb2650b9fe2f66e95f961))
* update pipeline ([b44cb1f](https://github.com/MicroTodoSuite/microservice-app-ops/commit/b44cb1f165d9484190b440f0c4f987e14575d7ac))
* update pipeline ([d46595a](https://github.com/MicroTodoSuite/microservice-app-ops/commit/d46595a84288b93f5c8738054b9c000204f3184e))
* update pipeline version terraform ([c35726a](https://github.com/MicroTodoSuite/microservice-app-ops/commit/c35726a873f8af3f52963e089111740d1a4ea96c))
* update pipeline with new variable ([25d383a](https://github.com/MicroTodoSuite/microservice-app-ops/commit/25d383a1408b7c799253878f1ac37f927d71cd62))
* update terraform version ([76abc6b](https://github.com/MicroTodoSuite/microservice-app-ops/commit/76abc6ba96e6054c831442a890c6b90b2f431098))


### Features

* remove file and delete test ([3fa0525](https://github.com/MicroTodoSuite/microservice-app-ops/commit/3fa05251e197d79d3a6765ee21ebbe663cfd6005))

# [1.3.0](https://github.com/MicroTodoSuite/microservice-app-ops/compare/v1.2.0...v1.3.0) (2025-04-25)


### Bug Fixes

* **infra:** remove an unused variable ([1f096b2](https://github.com/MicroTodoSuite/microservice-app-ops/commit/1f096b2c8172128fdaede5d8fa7c9892c94b40d5))
* **pipeline:** fix error when updating terraform backend secrets ([40d8787](https://github.com/MicroTodoSuite/microservice-app-ops/commit/40d87877f17b5ff40032e6e20e478560472a1660))
* **pipeline:** remove step for get storage account key ([f85c610](https://github.com/MicroTodoSuite/microservice-app-ops/commit/f85c610c205d38eba85878c48a95a63fbc12c4ba))
* **pipeline:** update pipeline of deploy ([41fd422](https://github.com/MicroTodoSuite/microservice-app-ops/commit/41fd42295c37c01634ce36c538bdb8553c152aa3))
* **pipeline:** update pipeline with state base infrastructure key ([1f3be28](https://github.com/MicroTodoSuite/microservice-app-ops/commit/1f3be286943add7a1669b329684630eccef6a942))


### Features

* **infra:** add script for Azure secrets configuration ([7d3e386](https://github.com/MicroTodoSuite/microservice-app-ops/commit/7d3e386a5cde3401b76c652a214c143c074e641a))

# [1.2.0](https://github.com/MicroTodoSuite/microservice-app-ops/compare/v1.1.0...v1.2.0) (2025-04-25)


### Bug Fixes

* **pipeline:** update backend pipeline ([459c887](https://github.com/MicroTodoSuite/microservice-app-ops/commit/459c887e65d2c80468fe0f8c5c1e206cb1ec76a9))


### Features

* **pipeline:** upgrade pipeline of backend ([7eb942d](https://github.com/MicroTodoSuite/microservice-app-ops/commit/7eb942da316204a6d231d2cc41194d8cbb98428f))

# [1.1.0](https://github.com/MicroTodoSuite/microservice-app-ops/compare/v1.0.0...v1.1.0) (2025-04-25)


### Features

* changelog added to semantic release ([6814f11](https://github.com/MicroTodoSuite/microservice-app-ops/commit/6814f11ee542277c4695c4c62d737a41ac733c66))
