# AWS IAM Role & Policy

Policy kiểm soát truy cập trong AWS có thể được phân loại theo nhiều góc nhìn cùng lúc: dùng để làm gì, áp dụng ở đâu, được lưu như thế nào, ai quản lý và kiểm soát quyền ra sao.

Các góc nhìn này chồng lên nhau. Trust policy của role đồng thời là resource-based policy; policy cấp quyền cho ứng dụng có thể vừa là identity-based policy, vừa là customer managed policy.

Tài liệu này trình bày các policy quản lý quyền truy cập trong IAM và những cơ chế liên quan, sau đó phân biệt chúng với các policy AWS phục vụ mục đích khác. Tài liệu nguồn được đối chiếu ngày 24/10/2026.

## 1. Bắt đầu từ IAM role: trust policy và permissions policy

IAM role là một danh tính AWS mà người dùng, ứng dụng hoặc dịch vụ được phép có thể đảm nhận (assume role). Khi đảm nhận role, bên sử dụng nhận thông tin xác thực tạm thời cho một phiên truy cập.

Khi tìm hiểu role, cần phân biệt trust policy với các permissions policy:

| Loại policy | Trả lời câu hỏi | Ví dụ |
| --- | --- | --- |
| Trust policy | Ai được tin cậy để đảm nhận role này, và với điều kiện nào? | Cho phép dịch vụ EC2 đảm nhận role của ứng dụng. |
| Permissions policy | Khi sử dụng role, được làm gì, trên tài nguyên nào và với điều kiện nào? | Cho phép đọc đối tượng trong bucket S3 của ứng dụng. |

Quyền đảm nhận role và quyền đọc dữ liệu ứng dụng là hai quyền riêng. Trust policy cho phép đảm nhận role; bản thân nó không cấp quyền đọc đối tượng S3.

Cách phân biệt này mô tả chức năng của các policy gắn với một role. Nó chưa bao quát toàn bộ các loại policy trong AWS.

Nguồn: [IAM roles](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles.html).

## 2. Phân loại theo loại policy và phạm vi áp dụng

Trang tổng quan của AWS hiện liệt kê chín loại policy hoặc cơ chế kiểm soát truy cập:

| Loại | Áp dụng ở đâu? | Mục đích chính |
| --- | --- | --- |
| Identity-based policy | IAM user, group hoặc role | Xác định quyền của danh tính. |
| Resource-based policy | Tài nguyên | Xác định những đối tượng nào được truy cập tài nguyên. |
| VPC endpoint policy | VPC endpoint | Kiểm soát truy cập đi qua endpoint. |
| Permissions boundary | IAM user hoặc role | Giới hạn quyền mà identity-based policies có thể cấp. |
| Service control policy (SCP) | Organizations root, OU hoặc account | Đặt giới hạn quyền cho các danh tính trong tài khoản thành viên. |
| Resource control policy (RCP) | Organizations root, OU hoặc account | Đặt giới hạn quyền đối với tài nguyên được hỗ trợ trong tài khoản thành viên. |
| Session policy | Phiên truy cập tạm thời | Thu hẹp quyền của phiên. |
| Access control list (ACL) | Tài nguyên hỗ trợ ACL | Cấp quyền truy cập tài nguyên bằng cơ chế ACL. |
| AWS RAM resource share | Nhóm tài nguyên được chia sẻ | Chia sẻ tài nguyên được hỗ trợ giữa các tài khoản hoặc trong tổ chức. |

Các nhóm trong danh sách có liên hệ với nhau và có thể chồng lấn. Ví dụ, AWS liệt kê riêng VPC endpoint policy, đồng thời mô tả endpoint policy là resource-based policy.

Nguồn: [Các loại policy AWS](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies.html#access_policy-types), [VPC endpoint policies](https://docs.aws.amazon.com/vpc/latest/privatelink/vpc-endpoints-access.html), [permissions boundaries](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_boundaries.html), [SCP và RCP](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_authorization_policies.html), và [session policies trong AssumeRole](https://docs.aws.amazon.com/STS/latest/APIReference/API_AssumeRole.html).

### Trust policy nằm ở đâu trong cách phân loại này?

Trust policy của role là resource-based policy gắn trực tiếp vào IAM role. S3 bucket policy là một ví dụ khác của resource-based policy.

IAM role có thể được nhìn từ hai phía:

- Là danh tính thực hiện hành động: các identity-based policies gắn vào role xác định quyền của nó.
- Là tài nguyên mà đối tượng khác muốn đảm nhận: trust policy xác định quan hệ tin cậy.

Resource-based policies được lưu trực tiếp trên tài nguyên. Chúng không phải các identity policy độc lập thuộc nhóm AWS managed hoặc customer managed.

Nguồn: [Resource-based policies](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies.html#policies_resource-based).

## 3. Phân loại theo cách lưu, khả năng dùng chung và bên quản lý

Với identity-based policies, cần phân biệt managed policy tồn tại độc lập với inline policy được nhúng trực tiếp vào một danh tính.

| Nhóm | Ai quản lý? | Có thể dùng chung cho nhiều danh tính? | Bạn có thể sửa quyền bên trong? |
| --- | --- | --- | --- |
| AWS managed policy | AWS | Có | Không sửa trực tiếp |
| Customer managed policy | Bạn hoặc tổ chức của bạn | Có | Có |
| Inline policy | Bạn hoặc tổ chức của bạn | Không có đối tượng policy dùng chung; nhúng riêng trong một user, group hoặc role | Có |

AWS managed và customer managed đều là managed policy độc lập, có ARN riêng. Inline policy thuộc về một danh tính và bị xóa khi danh tính đó bị xóa.

Ở đây có hai góc nhìn liên quan:

- Cách lưu và dùng chung: managed hoặc inline.
- Bên quản lý managed policy: AWS hoặc khách hàng.

AWS có thể cập nhật AWS managed policy. Khi bạn cập nhật customer managed policy, các danh tính đang gắn policy đó cùng sử dụng bản được cập nhật. Nếu sao chép nội dung vào nhiều inline policy, bạn tạo ra các bản riêng biệt.

Ví dụ, `AdministratorAccess` là AWS managed policy. Khi được gắn làm permissions policy cho IAM user hoặc role, nó đồng thời là identity-based policy.

Nguồn: [Managed policies và inline policies](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_managed-vs-inline.html).

## 4. Phân loại theo chức năng kiểm soát quyền: cấp quyền và đặt giới hạn

Các policy tham gia vào quyết định cho phép truy cập theo những cách khác nhau.

| Chức năng | Ví dụ | Ý nghĩa |
| --- | --- | --- |
| Cấp hoặc từ chối quyền truy cập | Identity-based và resource-based policies | Có thể chứa quyền cho phép và các quy tắc từ chối tường minh. |
| Cho phép đảm nhận role | Role trust policy | Kiểm soát việc đảm nhận role. |
| Giới hạn quyền do identity policy cấp | Permissions boundary | Đặt trần quyền mà identity-based policies có thể cấp. |
| Giới hạn quyền ở cấp tổ chức | SCP và RCP | Áp dụng giới hạn tập trung cho danh tính hoặc tài nguyên được hỗ trợ. |
| Giới hạn phiên truy cập tạm thời | Session policy | Thu hẹp quyền của phiên. |
| Kiểm soát đường truy cập | VPC endpoint policy | Bổ sung kiểm soát cho yêu cầu đi qua endpoint. |

Permissions boundary, SCP, RCP và session policy không tự cấp quyền. Một `Allow` trong các policy giới hạn này không thay thế cho quyền truy cập cần được cấp.

Một managed policy được dùng làm permissions boundary có chức năng khác với managed policy được gắn để cấp quyền. Vai trò của nó phụ thuộc vào cách được liên kết với danh tính.

Nguồn: [Permissions boundaries](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_boundaries.html), [policy kiểm soát quyền ở cấp tổ chức](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_authorization_policies.html), và [session policies trong AssumeRole](https://docs.aws.amazon.com/STS/latest/APIReference/API_AssumeRole.html).

Endpoint policy không thay thế các quyền mà dịch vụ đích yêu cầu. Giới hạn của nó áp dụng cho truy cập đi qua endpoint đó.

Nguồn: [VPC endpoint policies](https://docs.aws.amazon.com/vpc/latest/privatelink/vpc-endpoints-access.html).

## 5. Phân loại từng statement theo tác động: Allow và Deny

Mỗi statement trong JSON policy có trường `Effect`:

- `Allow`: cho phép các hành động được nêu khi statement áp dụng.
- `Deny`: từ chối tường minh các hành động được nêu khi statement áp dụng.

Một policy có thể chứa cả hai tác động trong các statement khác nhau. Vì vậy, "Allow policy" và "Deny policy" là cách gọi theo nội dung, không phải hai loại policy loại trừ nhau.

Một explicit deny áp dụng cho yêu cầu sẽ thắng allow. Yêu cầu cũng bị từ chối khi thiếu quyền cho phép cần thiết; trường hợp này là implicit deny, không phải một statement `Deny` tường minh.

Ý nghĩa của `Allow` còn phụ thuộc vào chức năng của policy: allow trong boundary xác định quyền nào có thể được cấp, thay vì tự cấp quyền đó.

Nguồn: [Effect](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_elements_effect.html) và [permissions boundaries](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_boundaries.html).

## 6. Phân loại theo phạm vi quyền và mức truy cập

Các mô tả như toàn quyền, chỉ đọc và quyền tùy chỉnh nói về mức độ bao phủ quyền, không nói policy được gắn ở đâu.

AWS phân loại hành động của dịch vụ thành năm mức truy cập:

| Mức truy cập | Ý nghĩa |
| --- | --- |
| List | Liệt kê tài nguyên hoặc xác định tài nguyên có tồn tại hay không. |
| Read | Đọc nội dung hoặc thuộc tính của tài nguyên. |
| Write | Tạo, sửa hoặc xóa tài nguyên. |
| Tagging | Thay đổi tag bằng các hành động dành riêng cho việc quản lý tag. |
| Permissions management | Quản lý quyền truy cập. |

Một policy có thể chứa nhiều mức truy cập, với toàn bộ hoặc chỉ một phần hành động trong mỗi mức. Ví dụ, `s3:GetObject` thuộc mức Read, còn `s3:PutObject` thuộc mức Write.

Các mức này mô tả hành động. Chúng chưa xác định đầy đủ tài nguyên nào được truy cập hoặc điều kiện nào cần đáp ứng.

Nguồn: [Các mức truy cập trong bản tóm tắt policy](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_understand-policy-summary-access-level-summaries.html).

Để mô tả chính xác phạm vi, cần xem:

- `Action`: những thao tác nào được đề cập.
- `Resource`: những tài nguyên nào được đề cập, khi loại policy đó sử dụng trường này.
- `Principal`: những đối tượng nào được đề cập, khi loại policy đó sử dụng trường này.
- `Condition`: điều kiện bổ sung, chẳng hạn thuộc tính phải khớp hoặc yêu cầu về ngữ cảnh truy cập.

Không phải mọi loại policy đều chấp nhận các trường theo cùng một cách. Đây là các thành phần của tài liệu policy, không phải các nhóm policy bổ sung.

Nguồn: [Các thành phần trong IAM JSON policy](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_elements.html).

## 7. Phân loại theo cách thiết kế phân quyền: RBAC và ABAC

| Mô hình | Căn cứ cấp quyền | Ví dụ |
| --- | --- | --- |
| Role-based access control (RBAC) | Vai trò công việc hoặc trách nhiệm trong tổ chức | Bộ policy khác nhau cho lập trình viên và kiểm toán viên. |
| Attribute-based access control (ABAC) | Thuộc tính, thường là tag của danh tính và tài nguyên | Cho phép truy cập khi tag Project của danh tính khớp tag Project của tài nguyên. |

Đây là các cách thiết kế phân quyền được triển khai bằng policy. Chúng tồn tại song song với cách phân loại identity-based và resource-based.

"Role" trong RBAC có nghĩa là vai trò công việc hoặc trách nhiệm; nó không đồng nghĩa với tài nguyên IAM role. Một thiết kế có thể kết hợp bộ quyền theo công việc với điều kiện dựa trên thuộc tính.

Nguồn: [ABAC và cách so sánh với RBAC](https://docs.aws.amazon.com/IAM/latest/UserGuide/introduction_attribute-based-access-control.html).

## 8. Phân loại theo quan hệ truy cập

Policy cũng có thể được mô tả theo quan hệ giữa bên gọi và đối tượng đích:

- Same-account: danh tính và đối tượng đích nằm trong cùng tài khoản AWS.
- Cross-account: danh tính và đối tượng đích nằm trong các tài khoản khác nhau.
- Truy cập của dịch vụ AWS: một dịch vụ AWS đảm nhận role để thực hiện công việc.
- Federated access: danh tính từ hệ thống xác thực bên ngoài truy cập thông qua role.

Đây là các tình huống sử dụng, không phải các dạng lưu policy riêng. Chúng có thể kết hợp với nhau: một phiên của danh tính liên kết cũng có thể truy cập tài nguyên ở tài khoản khác.

Với cross-account assume role, role đích phải thiết lập quan hệ tin cậy phù hợp và bên gọi phải có quyền gọi `sts:AssumeRole`. Chỉ nhìn trust policy chưa đủ để kết luận mọi bên gọi đều có thể đảm nhận role.

Nguồn: [IAM roles](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles.html) và [quyền gọi AssumeRole](https://docs.aws.amazon.com/STS/latest/APIReference/API_AssumeRole.html).

## 9. Phân biệt policy truy cập với những policy AWS khác

Từ "policy" trong AWS có phạm vi rộng hơn việc cấp quyền trong IAM. AWS Organizations còn có các policy quản lý cấu hình hoặc cách vận hành ở cấp tổ chức.

Ví dụ:

- Tag policies: chuẩn hóa tag của tài nguyên.
- Backup policies: quản lý tập trung các kế hoạch sao lưu.
- AI services opt-out policies: quản lý lựa chọn về thu thập dữ liệu của dịch vụ AI.
- Declarative policies: khai báo và duy trì tập trung cấu hình của dịch vụ được hỗ trợ.

AWS Organizations phân biệt authorization policies, gồm SCP và RCP, với nhóm declarative policies. Policy chuẩn hóa tag có mục đích khác với IAM policy cấp quyền truy cập S3.

Nguồn: [Quản lý policy trong AWS Organizations](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies.html).

## 10. Ví dụ tổng hợp: một role có nhiều cách phân loại

Xét role minh họa tên `ApplicationReadDataRole`:

1. Trust policy cho phép dịch vụ EC2 đảm nhận role.
2. Customer managed policy tên `ApplicationReadData` được gắn làm permissions policy, cho phép đọc đối tượng của ứng dụng trong S3.
3. Một permissions boundary tùy chọn giới hạn quyền mà các identity-based policies của role có thể cấp.

Cùng những thành phần này có thể được mô tả theo nhiều góc nhìn:

| Thành phần | Chức năng | Loại hoặc phạm vi | Cách lưu hoặc quản lý |
| --- | --- | --- | --- |
| Role trust policy | Cho phép đảm nhận role | Resource-based; gắn vào role | Lưu trực tiếp trên role |
| Policy ApplicationReadData | Cấp quyền cho ứng dụng | Identity-based; hành động mức Read | Customer managed; tồn tại độc lập và có thể dùng chung |
| Boundary tùy chọn | Giới hạn quyền do identity policy cấp | Permissions boundary trên role | Sử dụng một managed policy |

Permissions policy mô tả các thao tác S3 được cho phép. Trust policy xác định ai được sử dụng role. Boundary giới hạn quyền do identity policy cấp. Các policy ở cấp tổ chức, session policy, resource policy và explicit deny có liên quan cũng có thể ảnh hưởng đến yêu cầu truy cập.

Ví dụ này minh họa cách kết hợp các góc phân loại; nó không mô tả cấu hình đang được triển khai của repository này.

Nguồn: [IAM roles](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles.html), [managed policies và inline policies](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_managed-vs-inline.html), và [permissions boundaries](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_boundaries.html).
