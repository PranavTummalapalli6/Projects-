import { ApiProperty } from '@nestjs/swagger';

export class UploadDocumentResponseDto {
  @ApiProperty()
  id: string;

  @ApiProperty()
  originalName: string;

  @ApiProperty()
  status: string;

  @ApiProperty()
  createdAt: Date;
}
